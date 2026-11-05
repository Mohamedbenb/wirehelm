package tsnetbridge

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/netip"
	"strconv"
	"testing"
	"time"
)

func TestDebugPeerRequiresTailnetAddress(t *testing.T) {
	for _, ip := range []string{"100.64.0.10", "fd7a:115c:a1e0::1"} {
		if _, err := debugPeer(ip); err != nil {
			t.Fatal(ip, err)
		}
	}
	for _, ip := range []string{"127.0.0.1", "192.168.1.2", "8.8.8.8", "100.128.0.1", "pc.example", ""} {
		if _, err := debugPeer(ip); err == nil {
			t.Fatal("accepted", ip)
		}
	}
}
func fixtureDebugRelay(t *testing.T, peer string, expires time.Duration) (*debugRelay, net.Conn) {
	t.Helper()
	local, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { local.Close() })
	go func() {
		for {
			c, e := local.Accept()
			if e != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	remote, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	_, port, _ := net.SplitHostPort(local.Addr().String())
	number, _ := strconv.Atoi(port)
	ctx, cancel := context.WithCancel(context.Background())
	r := &debugRelay{listener: remote, allowed: netip.MustParseAddr(peer), localPort: number, expires: time.Now().Add(expires), sockets: map[net.Conn]bool{}, cancel: cancel}
	go r.serve(ctx)
	t.Cleanup(r.close)
	c, err := net.Dial("tcp", remote.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	c.SetDeadline(time.Now().Add(2 * time.Second))
	return r, c
}
func TestDebugRelayPreservesBinaryAndStopsConnections(t *testing.T) {
	r, c := fixtureDebugRelay(t, "127.0.0.1", time.Minute)
	input := bytes.Repeat([]byte{0, 255, 42, 128}, 8192)
	done := make(chan error, 1)
	go func() { _, err := c.Write(input); done <- err }()
	output := make([]byte, len(input))
	if _, err := io.ReadFull(c, output); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(input, output) {
		t.Fatal("data changed")
	}
	r.close()
	r.close()
	if _, err := c.Read(make([]byte, 1)); err == nil {
		t.Fatal("connection remained open")
	}
}
func TestDebugRelayRejectsOtherPeer(t *testing.T) {
	_, c := fixtureDebugRelay(t, "100.64.0.10", time.Minute)
	if _, err := c.Read(make([]byte, 1)); err == nil {
		t.Fatal("unlisted peer accepted")
	}
}
func TestDebugRelayExpires(t *testing.T) {
	_, c := fixtureDebugRelay(t, "127.0.0.1", 30*time.Millisecond)
	if _, err := c.Read(make([]byte, 1)); err == nil {
		t.Fatal("session remained open")
	}
}
func TestDebugRelayRejectsInvalidPortWithoutStartingNode(t *testing.T) {
	n := NewNode()
	defer n.Close()
	if err := n.StartDebugRelay(0, "100.64.0.10"); err == nil {
		t.Fatal("invalid port accepted")
	}
	if err := n.StartDebugRelay(5555, "127.0.0.1"); err == nil {
		t.Fatal("non-tailnet peer accepted")
	}
	n.StopDebugRelay()
	if n.DebugRelayStatus() == "" {
		t.Fatal("missing status")
	}
}
