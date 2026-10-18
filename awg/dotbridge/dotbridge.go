// dotbridge — UDP/TCP DNS on localhost forwarded over DNS-over-TLS.
// The carrier resolvers poison answers and the tunnel's resolver filters some
// names, but the tunnel carries TCP 853 untouched.
package main

import (
	"encoding/binary"
	"flag"
	"io"
	"log"
	"net"
	"time"
)

var (
	listen   = flag.String("listen", "127.0.0.2:5353", "local DNS address")
	upstream = flag.String("upstream", "1.1.1.1:853", "DoT server")
	sni      = flag.String("sni", "cloudflare-dns.com", "TLS server name")
)

func query(q []byte) ([]byte, error) {
	d := net.Dialer{Timeout: 5 * time.Second}
	c, err := tlsDial(&d, *upstream, *sni)
	if err != nil {
		return nil, err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(5 * time.Second))
	buf := make([]byte, 2+len(q))
	binary.BigEndian.PutUint16(buf, uint16(len(q)))
	copy(buf[2:], q)
	if _, err := c.Write(buf); err != nil {
		return nil, err
	}
	var n uint16
	if err := binary.Read(c, binary.BigEndian, &n); err != nil {
		return nil, err
	}
	resp := make([]byte, n)
	if _, err := io.ReadFull(c, resp); err != nil {
		return nil, err
	}
	return resp, nil
}

// Retry briefly: a restart races the previous instance releasing the port.
func listenPacketRetry() (net.PacketConn, error) {
	var err error
	for i := 0; i < 25; i++ {
		var pc net.PacketConn
		if pc, err = net.ListenPacket("udp", *listen); err == nil {
			return pc, nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return nil, err
}

func listenRetry() (net.Listener, error) {
	var err error
	for i := 0; i < 25; i++ {
		var ln net.Listener
		if ln, err = net.Listen("tcp", *listen); err == nil {
			return ln, nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return nil, err
}

func serveUDP() {
	pc, err := listenPacketRetry()
	if err != nil {
		log.Fatal(err)
	}
	for {
		buf := make([]byte, 4096)
		n, addr, err := pc.ReadFrom(buf)
		if err != nil {
			continue
		}
		go func(q []byte, addr net.Addr) {
			r, err := query(q)
			if err != nil {
				log.Printf("udp query: %v", err)
				return
			}
			pc.WriteTo(r, addr)
		}(append([]byte(nil), buf[:n]...), addr)
	}
}

func serveTCP() {
	ln, err := listenRetry()
	if err != nil {
		log.Fatal(err)
	}
	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			var n uint16
			c.SetDeadline(time.Now().Add(10 * time.Second))
			if err := binary.Read(c, binary.BigEndian, &n); err != nil {
				return
			}
			q := make([]byte, n)
			if _, err := io.ReadFull(c, q); err != nil {
				return
			}
			r, err := query(q)
			if err != nil {
				return
			}
			out := make([]byte, 2+len(r))
			binary.BigEndian.PutUint16(out, uint16(len(r)))
			copy(out[2:], r)
			c.Write(out)
		}(c)
	}
}

func main() {
	flag.Parse()
	go serveTCP()
	serveUDP()
}
