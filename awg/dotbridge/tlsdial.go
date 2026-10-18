package main

import (
	"crypto/tls"
	"net"
	"time"
)

func tlsDial(d *net.Dialer, addr, sni string) (*tls.Conn, error) {
	raw, err := d.Dial("tcp", addr)
	if err != nil {
		return nil, err
	}
	c := tls.Client(raw, &tls.Config{ServerName: sni, MinVersion: tls.VersionTLS12})
	c.SetDeadline(time.Now().Add(5 * time.Second))
	if err := c.Handshake(); err != nil {
		raw.Close()
		return nil, err
	}
	return c, nil
}
