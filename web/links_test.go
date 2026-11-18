package main

import (
  "encoding/base64"
  "encoding/json"
  "strings"
  "testing"
)

func TestParseVLESSReality(t *testing.T) {
  p, err := parseLink("vless://11111111-1111-1111-1111-111111111111@example.com:443?security=reality&sni=cdn.example.com&fp=chrome&pbk=PUBKEY&sid=abcd&type=ws&host=cdn.example.com&path=%2Fedge#test-node")
  if err != nil { t.Fatal(err) }
  if p.out["type"] != "vless" || p.label != "test-node" { t.Fatalf("unexpected parse: %#v", p) }
  tls := p.out["tls"].(map[string]any)
  if tls["server_name"] != "cdn.example.com" { t.Fatalf("wrong SNI: %v", tls["server_name"]) }
}

func TestParseTrojanAndHysteria2(t *testing.T) {
  tr, err := parseLink("trojan://secret@example.org:443?sni=front.example#eu")
  if err != nil { t.Fatal(err) }
  if tr.out["password"] != "secret" || tr.out["tls"].(map[string]any)["server_name"] != "front.example" { t.Fatalf("bad Trojan parse: %#v", tr.out) }
  hy, err := parseLink("hysteria2://secret@example.org:443?sni=front.example")
  if err != nil { t.Fatal(err) }
  if hy.out["type"] != "hysteria2" || hy.out["tls"].(map[string]any)["server_name"] != "front.example" { t.Fatalf("bad Hysteria2 parse: %#v", hy.out) }
}

func TestParseVMess(t *testing.T) {
  raw, _ := json.Marshal(map[string]any{"add":"vmess.example","port":"443","id":"uuid","net":"ws","tls":"tls","path":"/ws","ps":"test-node"})
  p, err := parseLink("vmess://" + base64.StdEncoding.EncodeToString(raw))
  if err != nil { t.Fatal(err) }
  if p.label != "test-node" || p.out["type"] != "vmess" { t.Fatalf("bad VMess parse: %#v", p) }
}

func TestParseShadowsocks(t *testing.T) {
  creds := base64.RawURLEncoding.EncodeToString([]byte("chacha20-ietf-poly1305:secret"))
  p, err := parseLink("ss://" + creds + "@ss.example:8388#ss-node")
  if err != nil { t.Fatal(err) }
  if p.label != "ss-node" || p.out["password"] != "secret" { t.Fatalf("bad SS parse: %#v", p) }
}

func TestRejectUnsupportedScheme(t *testing.T) {
  _, err := parseLink("ftp://example.com:21")
  if err == nil || !strings.Contains(err.Error(), "unsupported") { t.Fatal("expected unsupported scheme") }
}
