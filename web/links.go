package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type proxyLink struct {
	name string
	raw string
	out map[string]any
}

var cleanLinkName = regexp.MustCompile("[^A-Za-z0-9_-]+")

func importLinks(text string) ([]string, []string, error) {
	if len(text)>256*1024{return nil,nil,errors.New("link text is too large")}
	added,skipped:=[]string{},[]string{}
	seen:=map[string]bool{}
	for _,raw:=range strings.Fields(text){
		p,err:=parseLink(raw);if err!=nil{skipped=append(skipped,raw);continue}
		if seen[p.raw]{continue};seen[p.raw]=true
		name:=p.name;base:=name;n:=2
		for exists(filepath.Join("/data/zltx28/singbox/links",name+".json")){name=fmt.Sprintf("%s-%d",base,n);n++}
		tun,err:=tunnelJSON(p.out);if err!=nil{return added,skipped,err}
		test,err:=testJSON(p.out);if err!=nil{return added,skipped,err}
		dir:="/data/zltx28/singbox/links"
		if err=os.MkdirAll(dir,0700);err!=nil{return added,skipped,err}
		if err=atomicWrite(filepath.Join(dir,name+".json"),tun,0600);err!=nil{return added,skipped,err}
		if err=atomicWrite(filepath.Join(dir,name+".test.json"),test,0600);err!=nil{return added,skipped,err}
		if err=atomicWrite(filepath.Join(dir,name+".link"),[]byte(p.raw+"\n"),0600);err!=nil{return added,skipped,err}
		added=append(added,name)
	}
	if len(added)==0&&len(skipped)>0{return added,skipped,errors.New("no supported links found: VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and SOCKS5")}
	return added,skipped,nil
}
func exists(p string)bool{_,e:=os.Stat(p);return e==nil}
func decode64(s string)([]byte,error){
	s=strings.NewReplacer("-","+","_","/").Replace(strings.TrimSpace(s))
	for len(s)%4!=0{s+="="}
	if b,e:=base64.StdEncoding.DecodeString(s);e==nil{return b,nil}
	return base64.RawStdEncoding.DecodeString(strings.TrimRight(s,"="))
}
func parseLink(raw string)(*proxyLink,error){
	raw=strings.TrimSpace(raw)
	lower:=strings.ToLower(raw)
	if strings.HasPrefix(lower,"vmess://"){return parseVMess(raw)}
	if strings.HasPrefix(lower,"ss://"){return parseSS(raw)}
	u,err:=url.Parse(raw);if err!=nil{return nil,err}
	scheme:=strings.ToLower(u.Scheme);host:=u.Hostname();port,_:=strconv.Atoi(u.Port())
	if host==""||port<1||port>65535{return nil,errors.New("link needs a hostname and valid port")}
	q:=u.Query();password:="";if u.User!=nil{password,_=u.User.Password();if password==""{password=u.User.Username()}}
	out:=map[string]any{"tag":"proxy","server":host,"server_port":port}
	switch scheme{
	case "vless":
		if u.User==nil||u.User.Username()==""{return nil,errors.New("VLESS UUID missing")}
		out["type"]="vless";out["uuid"]=u.User.Username();if f:=q.Get("flow");f!=""{out["flow"]=f}
		if tls:=tlsConfig(q,host);tls!=nil{out["tls"]=tls};if tr:=transport(q);tr!=nil{out["transport"]=tr}
	case "trojan":
		if password==""{return nil,errors.New("Trojan password missing")};out["type"]="trojan";out["password"]=password
		tls:=tlsConfig(q,host);if tls==nil{tls=map[string]any{"enabled":true,"server_name":host}};out["tls"]=tls
		if tr:=transport(q);tr!=nil{out["transport"]=tr}
	case "hysteria2","hy2":
		if password==""{return nil,errors.New("Hysteria2 password missing")};out["type"]="hysteria2";out["password"]=password
		tls:=tlsConfig(q,host);if tls==nil{tls=map[string]any{"enabled":true,"server_name":host}};out["tls"]=tls
		if obfs:=q.Get("obfs");obfs!=""{out["obfs"]=map[string]any{"type":obfs,"password":q.Get("obfs-password")}}
	case "socks","socks5":
		out["type"]="socks";out["version"]="5";if u.User!=nil{out["username"]=u.User.Username();if p,ok:=u.User.Password();ok{out["password"]=p}}
	default:return nil,fmt.Errorf("unsupported scheme %s",scheme)
	}
	name:=safeLinkName(scheme+"-"+host+"-"+strconv.Itoa(port))
	return &proxyLink{name:name,raw:raw,out:out},nil
}
func parseVMess(raw string)(*proxyLink,error){
	payload:=raw[len("vmess://"):];b,e:=decode64(payload);if e!=nil{return nil,errors.New("invalid VMess base64")}
	var v map[string]any;if e=json.Unmarshal(b,&v);e!=nil{return nil,errors.New("invalid VMess JSON")}
	get:=func(k string)string{switch x:=v[k].(type){case string:return x;case float64:return strconv.Itoa(int(x))};return ""}
	host:=get("add");port,_:=strconv.Atoi(get("port"));id:=get("id");if host==""||port<1||port>65535||id==""{return nil,errors.New("VMess needs add, port and id")}
	out:=map[string]any{"type":"vmess","tag":"proxy","server":host,"server_port":port,"uuid":id,"alter_id":intString(get("aid")),"security":first(get("scy"),"auto")}
	if strings.EqualFold(get("tls"),"tls"){sni:=first(get("sni"),get("host"),host);tls:=map[string]any{"enabled":true,"server_name":sni};if fp:=get("fp");fp!=""{tls["utls"]=map[string]any{"enabled":true,"fingerprint":fp}};out["tls"]=tls}
	network:=strings.ToLower(get("net"));path:=first(get("path"),"/");h:=get("host")
	switch network{case "ws":tr:=map[string]any{"type":"ws","path":path};if h!=""{tr["headers"]=map[string]string{"Host":h}};out["transport"]=tr
	case "grpc":out["transport"]=map[string]any{"type":"grpc","service_name":path}
	case "h2","http":hosts:=[]string{host};if h!=""{hosts=[]string{h}};out["transport"]=map[string]any{"type":"http","path":path,"host":hosts}}
	return &proxyLink{name:safeLinkName("vmess-"+host+"-"+strconv.Itoa(port)),raw:raw,out:out},nil
}
func parseSS(raw string)(*proxyLink,error){
	body:=raw[len("ss://"):];label:="";if i:=strings.Index(body,"#");i>=0{label,_=url.QueryUnescape(body[i+1:]);body=body[:i]};if i:=strings.Index(body,"?");i>=0{body=body[:i]}
	var creds,server string
	if i:=strings.LastIndex(body,"@");i>=0{creds=body[:i];server=body[i+1:];b,e:=decode64(creds);if e==nil{creds=string(b)}else{creds,_=url.QueryUnescape(creds)}}else{b,e:=decode64(body);if e!=nil{return nil,errors.New("invalid Shadowsocks base64")};i=strings.LastIndex(string(b),"@");if i<0{return nil,errors.New("invalid Shadowsocks payload")};creds=string(b[:i]);server=string(b[i+1:])}
	i:=strings.Index(creds,":");if i<1{return nil,errors.New("invalid Shadowsocks credentials")};method,password:=creds[:i],creds[i+1:]
	u,e:=url.Parse("//"+server);if e!=nil{return nil,e};host:=u.Hostname();port,_:=strconv.Atoi(u.Port());if host==""||port<1||port>65535{return nil,errors.New("Shadowsocks needs host and port")}
	if label==""{label=host};_ = label
	return &proxyLink{name:safeLinkName("ss-"+host+"-"+strconv.Itoa(port)),raw:raw,out:map[string]any{"type":"shadowsocks","tag":"proxy","server":host,"server_port":port,"method":method,"password":password}},nil
}
func tlsConfig(q url.Values,host string)map[string]any{
	security:=strings.ToLower(q.Get("security"));if security!="tls"&&security!="xtls"&&security!="reality"{return nil}
	sni:=first(q.Get("sni"),q.Get("peer"),q.Get("host"),host);v:=map[string]any{"enabled":true,"server_name":sni}
	if security=="reality"{fp:=first(q.Get("fp"),"chrome");v["utls"]=map[string]any{"enabled":true,"fingerprint":fp};v["reality"]=map[string]any{"enabled":true,"public_key":q.Get("pbk"),"short_id":q.Get("sid")}}else if fp:=q.Get("fp");fp!=""{v["utls"]=map[string]any{"enabled":true,"fingerprint":fp}}
	if q.Get("allowinsecure")=="1"||q.Get("insecure")=="1"{v["insecure"]=true};if a:=q.Get("alpn");a!=""{v["alpn"]=strings.Split(a,",")};return v
}
func transport(q url.Values)map[string]any{
	t:=strings.ToLower(q.Get("type"));path:=first(q.Get("path"),"/");host:=q.Get("host")
	switch t{case "ws":v:=map[string]any{"type":"ws","path":path};if host!=""{v["headers"]=map[string]string{"Host":host}};return v
	case "grpc":return map[string]any{"type":"grpc","service_name":first(q.Get("serviceName"),q.Get("servicename"),path)}
	case "httpupgrade":v:=map[string]any{"type":"httpupgrade","path":path};if host!=""{v["host"]=host};return v
	case "http","h2":hosts:=[]string{};if host!=""{hosts=append(hosts,host)};return map[string]any{"type":"http","path":path,"host":hosts}}
	return nil
}
func safeLinkName(s string)string{n:=strings.Trim(cleanLinkName.ReplaceAllString(s,"-"),"-");if len(n)>48{n=n[:48]};return n}
func first(v ...string)string{for _,s:=range v{if s!=""{return s}};return ""}
func intString(s string)int{n,_:=strconv.Atoi(s);return n}
func tunnelJSON(out map[string]any)([]byte,error){
	v:=map[string]any{"log":map[string]any{"level":"warn"},"inbounds":[]any{map[string]any{"type":"tun","tag":"tun-in","interface_name":"sb0","address":[]string{"10.77.0.1/30"},"mtu":1420,"stack":"gvisor","auto_route":false,"strict_route":false}},"outbounds":[]any{out,map[string]any{"type":"direct","tag":"direct"}},"route":map[string]any{"final":"proxy"}}
	return json.MarshalIndent(v,"","  ")
}
func testJSON(out map[string]any)([]byte,error){
	v:=map[string]any{"log":map[string]any{"level":"error"},"inbounds":[]any{map[string]any{"type":"mixed","tag":"test-in","listen":"127.0.0.1","listen_port":18080}},"outbounds":[]any{out,map[string]any{"type":"direct","tag":"direct"}},"route":map[string]any{"final":"proxy"}}
	return json.MarshalIndent(v,"","  ")
}
