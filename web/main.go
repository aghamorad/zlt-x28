package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

//go:embed static/*
var assets embed.FS

const authPath = "/data/zltx28/web/password"
var validName = regexp.MustCompile("^[A-Za-z0-9_-]{1,48}$")

type app struct {
	password string
	lan *net.IPNet
	mu sync.Mutex
	opMu sync.Mutex
	testMu sync.Mutex
	sessions map[string]time.Time
	attempts map[string][]time.Time
}

func main() {
	addr := flag.String("addr", "0.0.0.0:8080", "listen address")
	auth := flag.String("auth-file", authPath, "password file")
	cidr := flag.String("lan-cidr", "192.168.70.0/24", "permitted LAN subnet")
	initAuth := flag.Bool("init-auth", false, "create password if missing")
	flag.Parse()
	password, created, err := loadPassword(*auth)
	if err != nil { log.Fatal(err) }
	if *initAuth {
		if created { fmt.Printf("ZLT_WEB_PASSWORD=%s\n", password) }
		return
	}
	_, lan, err := net.ParseCIDR(*cidr)
	if err != nil { log.Fatal(err) }
	a := &app{password:password, lan:lan, sessions:map[string]time.Time{}, attempts:map[string][]time.Time{}}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/login", a.login)
	mux.HandleFunc("POST /api/logout", a.protect(a.logout))
	mux.HandleFunc("GET /api/status", a.protect(a.status))
	mux.HandleFunc("POST /api/vpn", a.protect(a.vpn))
	mux.HandleFunc("POST /api/select", a.protect(a.selectConfig))
	mux.HandleFunc("POST /api/import", a.protect(a.importConfig))
	mux.HandleFunc("POST /api/remove", a.protect(a.removeConfig))
	mux.HandleFunc("POST /api/test", a.protect(a.testAll))
	mux.HandleFunc("POST /api/test-one", a.protect(a.testOne))
	mux.HandleFunc("GET /", a.static)
	handler := a.lanOnly(mux)
	srv := &http.Server{Addr:*addr, Handler:handler, ReadHeaderTimeout:5*time.Second, IdleTimeout:60*time.Second, WriteTimeout:15*time.Minute, MaxHeaderBytes:1<<20}
	log.Printf("ZLT dashboard listening on %s; allowed LAN %s", *addr, *cidr)
	log.Fatal(srv.ListenAndServe())
}

func loadPassword(path string) (string, bool, error) {
	if b, err := os.ReadFile(path); err == nil {
		p := strings.TrimSpace(string(b)); if len(p)<20 { return "",false,errors.New("stored password is too short") }; return p,false,nil
	} else if !os.IsNotExist(err) { return "",false,err }
	if err:=os.MkdirAll(filepath.Dir(path),0700); err!=nil{return "",false,err}
	b:=make([]byte,24); if _,err:=rand.Read(b);err!=nil{return "",false,err}
	p:=hex.EncodeToString(b); if err:=os.WriteFile(path,[]byte(p+"\n"),0600);err!=nil{return "",false,err}
	return p,true,nil
}

func (a *app) lanOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
		if r.Host!="192.168.70.1:8080" && r.Host!="192.168.70.1" { http.Error(w,"forbidden host",403); return }
		host,_,err:=net.SplitHostPort(r.RemoteAddr); ip:=net.ParseIP(host)
		if err!=nil || ip==nil || (!ip.IsLoopback()&&!a.lan.Contains(ip)){http.Error(w,"forbidden",403);return}
		w.Header().Set("X-Content-Type-Options","nosniff")
		w.Header().Set("X-Frame-Options","DENY")
		w.Header().Set("Referrer-Policy","no-referrer")
		w.Header().Set("Content-Security-Policy","default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w,r)
	})
}

func (a *app) static(w http.ResponseWriter,r *http.Request) {
	if r.Method!=http.MethodGet { fail(w,405,"method not allowed");return }
	path:=strings.TrimPrefix(filepath.Clean("/"+r.URL.Path),"/"); if path==""||path=="." {path="index.html"}
	if strings.Contains(path,".."){http.NotFound(w,r);return}
	b,err:=assets.ReadFile("static/"+path);if err!=nil{http.NotFound(w,r);return}
	ct:="application/octet-stream";switch filepath.Ext(path){case ".html":ct="text/html; charset=utf-8";case ".css":ct="text/css; charset=utf-8";case ".js":ct="text/javascript; charset=utf-8";case ".json":ct="application/manifest+json";case ".svg":ct="image/svg+xml"}
	w.Header().Set("Content-Type",ct);w.Header().Set("Cache-Control","no-cache");_,_=w.Write(b)
}

func (a *app) login(w http.ResponseWriter,r *http.Request) {
	if !originOK(r){fail(w,403,"request origin rejected");return}
	ip:=clientIP(r);a.mu.Lock();now:=time.Now();old:=a.attempts[ip][:0];for _,t:=range a.attempts[ip]{if now.Sub(t)<time.Minute{old=append(old,t)}};if len(old)>=6{a.attempts[ip]=old;a.mu.Unlock();fail(w,429,"too many attempts; wait one minute");return};a.attempts[ip]=append(old,now);a.mu.Unlock()
	var b struct{Password string `json:"password"`};if !decode(w,r,&b){return}
	x,y:=sha256.Sum256([]byte(b.Password)),sha256.Sum256([]byte(a.password));if subtle.ConstantTimeCompare(x[:],y[:])!=1{fail(w,401,"incorrect password");return}
	raw:=make([]byte,32);if _,err:=rand.Read(raw);err!=nil{fail(w,500,"could not create session");return};token:=hex.EncodeToString(raw)
	a.mu.Lock();a.sessions[token]=time.Now().Add(12*time.Hour);a.mu.Unlock()
	http.SetCookie(w,&http.Cookie{Name:"zlt_session",Value:token,Path:"/",HttpOnly:true,SameSite:http.SameSiteStrictMode,MaxAge:43200})
	write(w,200,map[string]any{"ok":true})
}
func (a *app) protect(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter,r *http.Request){
		if !originOK(r){fail(w,403,"request origin rejected");return}
		c,err:=r.Cookie("zlt_session");if err!=nil{fail(w,401,"sign in again");return}
		a.mu.Lock();expiry,ok:=a.sessions[c.Value];if ok&&time.Now().After(expiry){delete(a.sessions,c.Value);ok=false};a.mu.Unlock()
		if !ok{fail(w,401,"session expired; sign in again");return};next(w,r)
	}
}
func (a *app) logout(w http.ResponseWriter,r *http.Request){if c,e:=r.Cookie("zlt_session");e==nil{a.mu.Lock();delete(a.sessions,c.Value);a.mu.Unlock()};http.SetCookie(w,&http.Cookie{Name:"zlt_session",Value:"",Path:"/",HttpOnly:true,SameSite:http.SameSiteStrictMode,MaxAge:-1});write(w,200,map[string]any{"ok":true})}
func originOK(r *http.Request)bool{o:=r.Header.Get("Origin");if o==""{return true};return strings.EqualFold(strings.TrimPrefix(strings.TrimPrefix(o,"http://"),"https://"),r.Host)}
func clientIP(r *http.Request)string{h,_,_:=net.SplitHostPort(r.RemoteAddr);return h}
func decode(w http.ResponseWriter,r *http.Request,v any)bool{r.Body=http.MaxBytesReader(w,r.Body,256*1024);defer r.Body.Close();if err:=json.NewDecoder(r.Body).Decode(v);err!=nil{fail(w,400,"invalid request body");return false};return true}
func write(w http.ResponseWriter,status int,v any){w.Header().Set("Content-Type","application/json; charset=utf-8");w.WriteHeader(status);_=json.NewEncoder(w).Encode(v)}
func fail(w http.ResponseWriter,status int,msg string){write(w,status,map[string]string{"error":msg})}

func run(timeout time.Duration,args ...string)(string,error){
	ctx,cancel:=context.WithTimeout(context.Background(),timeout);defer cancel()
	cmd:=exec.CommandContext(ctx,"/usr/bin/vpn",args...);b,err:=cmd.CombinedOutput()
	if ctx.Err()!=nil{return string(b),ctx.Err()};if err!=nil{return string(b),fmt.Errorf("%s",strings.TrimSpace(string(b)))};return string(b),nil
}
func lines(s string)[]string{out:=[]string{};for _,v:=range strings.Split(s,"\n"){v=strings.TrimSpace(v);if v!=""&&!strings.HasPrefix(v,"FAILED:"){out=append(out,v)}};return out}
func line(s,prefix string)string{for _,v:=range strings.Split(s,"\n"){v=strings.TrimSpace(v);if strings.HasPrefix(v,prefix){return strings.TrimSpace(strings.TrimPrefix(v,prefix))}};return "—"}

func (a *app) status(w http.ResponseWriter,r *http.Request){
	awg,_:=run(15*time.Second,"awg","status");sb,_:=run(10*time.Second,"sb","status");cfg,_:=run(10*time.Second,"awg","list");lnk,_:=run(10*time.Second,"sb","list")
	awgOn:=strings.Contains(awg,"daemon   : running")&&strings.Contains(awg,"route    : default dev awg0")
	sbOn:=strings.Contains(sb,"daemon   : running")&&strings.Contains(sb,"route    : default dev sb0")
	engine:="off";if awgOn{engine="awg"}else if sbOn{engine="sb"}
	links:=[]map[string]string{};for _,n:=range lines(lnk){b,_:=os.ReadFile("/data/zltx28/singbox/links/"+n+".link");raw:=strings.TrimSpace(string(b));label:=n;if p,e:=parseLink(raw);e==nil&&p.label!=""{label=p.label};links=append(links,map[string]string{"name":n,"label":label})}
	exit:=line(awg,"exit IP  : ");if engine=="sb"{exit=line(sb,"exit IP  : ")}
	write(w,200,map[string]any{"engine":engine,"vpnOn":awgOn||sbOn,"awgOn":awgOn,"sbOn":sbOn,"awgStatus":strings.TrimSpace(awg),"sbStatus":strings.TrimSpace(sb),"configs":lines(cfg),"links":links,"exitIP":exit})
}
func (a *app) vpn(w http.ResponseWriter,r *http.Request){
	a.opMu.Lock(); defer a.opMu.Unlock()
	var b struct{Engine string `json:"engine"`;Action string `json:"action"`};if !decode(w,r,&b){return}
	if (b.Engine!="awg"&&b.Engine!="sb")||(b.Action!="on"&&b.Action!="off"&&b.Action!="restart"){fail(w,400,"unsupported engine or action");return}
	out,err:=run(150*time.Second,b.Engine,b.Action);if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return};write(w,200,map[string]any{"ok":true,"output":strings.TrimSpace(out)})
}
func (a *app) selectConfig(w http.ResponseWriter,r *http.Request){
	a.opMu.Lock(); defer a.opMu.Unlock()
	var b struct{Engine string `json:"engine"`;Name string `json:"name"`};if !decode(w,r,&b){return}
	if (b.Engine!="awg"&&b.Engine!="sb")||!validName.MatchString(b.Name){fail(w,400,"invalid engine or name");return}
	out,err:=run(30*time.Second,b.Engine,"use",b.Name);if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return}
	st,_:=run(15*time.Second,b.Engine,"status","quick");if strings.Contains(st,"daemon   : running"){out,err=run(150*time.Second,b.Engine,"restart");if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return}}
	write(w,200,map[string]any{"ok":true,"output":strings.TrimSpace(out)})
}
func atomicWrite(path string,b []byte,mode os.FileMode)error{if err:=os.MkdirAll(filepath.Dir(path),0700);err!=nil{return err};tmp:=path+".tmp";if err:=os.WriteFile(tmp,b,mode);err!=nil{return err};if err:=os.Chmod(tmp,mode);err!=nil{return err};return os.Rename(tmp,path)}
func (a *app) importConfig(w http.ResponseWriter,r *http.Request){
	a.opMu.Lock(); defer a.opMu.Unlock()
	var b struct{Kind string `json:"kind"`;Name string `json:"name"`;Content string `json:"content"`;Text string `json:"text"`};if !decode(w,r,&b){return}
	if b.Kind=="awg"{
		if !validName.MatchString(b.Name){fail(w,400,"name must use letters, numbers, _ or -");return};if len(b.Content)<30||!strings.Contains(b.Content,"[Interface]")||!strings.Contains(b.Content,"[Peer]"){fail(w,400,"invalid WireGuard/AmneziaWG .conf file");return}
		path:="/etc/amneziawg/awg0.conf."+b.Name;if _,e:=os.Stat(path);e==nil{fail(w,409,"that config name already exists");return}
		if err:=atomicWrite(path,[]byte(strings.TrimSpace(b.Content)+"\n"),0600);err!=nil{fail(w,500,err.Error());return}
		out,err:=run(30*time.Second,"awg","use",b.Name);if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return}
		st,_:=run(15*time.Second,"awg","status","quick");if strings.Contains(st,"daemon   : running"){out,err=run(150*time.Second,"awg","restart");if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return}}
		write(w,200,map[string]any{"ok":true,"added":[]string{b.Name},"output":out});return
	}
	if b.Kind=="links"{
		if _,err:=os.Stat("/data/zltx28/bin/sing-box");err!=nil{fail(w,409,"sing-box is not installed on this router");return}
		added,skipped,err:=importLinks(b.Text);if err!=nil{fail(w,400,err.Error());return};write(w,200,map[string]any{"ok":true,"added":added,"skipped":skipped});return
	}
	fail(w,400,"kind must be awg or links")
}
func (a *app) removeConfig(w http.ResponseWriter,r *http.Request){
	a.opMu.Lock(); defer a.opMu.Unlock()
	var b struct{Engine string `json:"engine"`;Name string `json:"name"`};if !decode(w,r,&b){return};if !validName.MatchString(b.Name){fail(w,400,"invalid name");return}
	if b.Engine=="sb"{out,err:=run(60*time.Second,"sb","remove",b.Name);if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return};write(w,200,map[string]any{"ok":true,"output":out});return}
	if b.Engine=="awg"{p:="/etc/amneziawg/awg0.conf."+b.Name;if _,err:=os.Stat(p);err!=nil{fail(w,404,"config not found");return};if err:=os.Rename(p,p+fmt.Sprintf(".disabled-%d",time.Now().Unix()));err!=nil{fail(w,500,err.Error());return};write(w,200,map[string]any{"ok":true});return}
	fail(w,400,"unknown engine")
}
func (a *app) testAll(w http.ResponseWriter,r *http.Request){a.testMu.Lock(); defer a.testMu.Unlock(); out,err:=run(13*time.Minute,"sb","testall");if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return};results:=[]map[string]string{};for _,v:=range strings.Split(out,"\n"){if strings.HasPrefix(v,"RESULT|"){p:=strings.Split(v,"|");if len(p)>=5{results=append(results,map[string]string{"name":p[1],"code":p[2],"latencyMs":p[3],"bytesPerSecond":p[4]})}}};sort.SliceStable(results,func(i,j int)bool{li,_:=strconv.Atoi(results[i]["latencyMs"]);lj,_:=strconv.Atoi(results[j]["latencyMs"]);if li==0{return false};if lj==0{return true};if li!=lj{return li<lj};si,_:=strconv.ParseFloat(results[i]["bytesPerSecond"],64);sj,_:=strconv.ParseFloat(results[j]["bytesPerSecond"],64);return si>sj});write(w,200,map[string]any{"ok":true,"results":results})}
func (a *app) testOne(w http.ResponseWriter,r *http.Request){a.testMu.Lock(); defer a.testMu.Unlock(); var b struct{Name string `json:"name"`};if !decode(w,r,&b){return};if !validName.MatchString(b.Name){fail(w,400,"invalid name");return};out,err:=run(120*time.Second,"sb","test",b.Name);if err!=nil{write(w,502,map[string]any{"error":err.Error(),"output":out});return};for _,v:=range strings.Split(out,"\n"){if strings.HasPrefix(v,"RESULT|"){p:=strings.Split(v,"|");if len(p)>=5{write(w,200,map[string]any{"ok":true,"name":p[1],"code":p[2],"latencyMs":p[3],"bytesPerSecond":p[4]});return}}};write(w,200,map[string]any{"ok":true,"output":strings.TrimSpace(out)})}
