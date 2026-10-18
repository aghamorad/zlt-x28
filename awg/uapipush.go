// uapipush — push a wg-quick-style AWG config straight to an amneziawg-go UAPI
// socket. Needed because the router's awgctl predates header_protection_key.
package main

import (
	"bufio"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"strings"
)

func hexKey(s string) string {
	b, err := base64.StdEncoding.DecodeString(strings.TrimSpace(s))
	if err != nil {
		fmt.Fprintln(os.Stderr, "bad key:", err)
		os.Exit(1)
	}
	return hex.EncodeToString(b)
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: uapipush <socket> <config>")
		os.Exit(2)
	}
	conf, err := os.Open(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	var out strings.Builder
	out.WriteString("set=1\n")
	sc := bufio.NewScanner(conf)
	sc.Buffer(make([]byte, 0, 1024*1024), 1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		lk := strings.ToLower(k)
		switch lk {
		case "address", "dns", "mtu", "table", "fwmark", "saveconfig", "postup", "postdown", "preup", "predown":
			continue
		case "privatekey":
			out.WriteString("private_key=" + hexKey(v) + "\n")
		case "publickey":
			out.WriteString("public_key=" + hexKey(v) + "\n")
		case "presharedkey":
			out.WriteString("preshared_key=" + hexKey(v) + "\n")
		case "listenport":
			out.WriteString("listen_port=" + v + "\n")
		case "jc":
			out.WriteString("jc=" + v + "\n")
		case "jmin":
			out.WriteString("jmin=" + v + "\n")
		case "jmax":
			out.WriteString("jmax=" + v + "\n")
		case "s1", "s2", "s3", "s4":
			out.WriteString(lk + "=" + v + "\n")
		case "h1", "h2", "h3", "h4":
			out.WriteString(lk + "=" + v + "\n")
		case "i1", "i2", "i3", "i4", "i5":
			out.WriteString(lk + "=" + v + "\n")
		case "headerprotectionkey":
			out.WriteString("header_protection_key=" + hexKey(v) + "\n")
		case "rekeyaftertime":
			out.WriteString("rekey_after_time=" + v + "\n")
		case "rekeytimeout":
			out.WriteString("rekey_timeout=" + v + "\n")
		case "rejectaftertime":
			out.WriteString("reject_after_time=" + v + "\n")
		case "keepalivetimeout":
			out.WriteString("keepalive_timeout=" + v + "\n")
		case "maxhandshakeattempts":
			out.WriteString("max_handshake_attempts=" + v + "\n")
		case "contentpaddingaddition":
			out.WriteString("content_padding_addition=" + v + "\n")
		case "randomtrailers":
			out.WriteString("random_trailers=" + v + "\n")
		case "disablecookies":
			out.WriteString("disable_cookies=" + v + "\n")
		case "endpoint":
			out.WriteString("endpoint=" + v + "\n")
		case "persistentkeepalive":
			out.WriteString("persistent_keepalive_interval=" + v + "\n")
		case "allowedips":
			for _, ip := range strings.Split(v, ",") {
				out.WriteString("allowed_ip=" + strings.TrimSpace(ip) + "\n")
			}
		}
	}
	out.WriteString("\n")

	c, err := net.Dial("unix", os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "dial:", err)
		os.Exit(1)
	}
	defer c.Close()
	if _, err := c.Write([]byte(out.String())); err != nil {
		fmt.Fprintln(os.Stderr, "write:", err)
		os.Exit(1)
	}
	rd := bufio.NewReader(c)
	for {
		line, err := rd.ReadString('\n')
		fmt.Print(line)
		if strings.HasPrefix(line, "errno=") || err != nil {
			break
		}
	}
}
