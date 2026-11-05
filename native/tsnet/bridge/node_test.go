package tsnetbridge

import (
	"bytes"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

func pipeNode(t *testing.T) (*Node, net.Conn) {
	t.Helper()
	local, remote := net.Pipe()
	node := NewNode()
	node.connections[1] = &connection{conn: local}
	t.Cleanup(func() { node.Close(); remote.Close() })
	return node, remote
}

func TestReadTimeoutEOFAndRecovery(t *testing.T) {
	// Use TCP for EOF: net.Pipe rejects SetReadDeadline once its peer closes,
	// whereas a TCP socket remains readable until its EOF is consumed.
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	remote, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	local, err := listener.Accept()
	if err != nil {
		remote.Close()
		t.Fatal(err)
	}
	node := NewNode()
	node.connections[1] = &connection{conn: local}
	t.Cleanup(func() { node.Close(); remote.Close() })
	if _, err := node.Read(1, 64, 10); err == nil || err.Error() != "TSNET_READ_TIMEOUT" {
		t.Fatalf("timeout: %v", err)
	}
	go func() { remote.Write([]byte{0, 255, 42}); remote.Close() }()
	data, err := node.Read(1, 64, 1000)
	if err != nil || !bytes.Equal(data, []byte{0, 255, 42}) {
		t.Fatalf("read: %v %v", data, err)
	}
	data, err = node.Read(1, 64, 1000)
	if err != nil || len(data) != 0 {
		t.Fatalf("EOF: %v %v", data, err)
	}
}

type partialConn struct{ net.Conn }

func (c partialConn) Write(data []byte) (int, error) {
	if len(data) > 3 {
		data = data[:3]
	}
	return c.Conn.Write(data)
}

func TestWriteHandlesPartialWrites(t *testing.T) {
	node, remote := pipeNode(t)
	node.connections[1].conn = partialConn{node.connections[1].conn}
	input := bytes.Repeat([]byte{0, 255, 128, 1}, 200)
	received := make(chan []byte, 1)
	go func() { data := make([]byte, len(input)); io.ReadFull(remote, data); received <- data }()
	count, err := node.Write(1, input, 1000)
	if err != nil || count != len(input) {
		t.Fatalf("write: %d %v", count, err)
	}
	if !bytes.Equal(<-received, input) {
		t.Fatal("bytes changed or reordered")
	}
}

func TestCloseUnblocksReadAndIsIdempotent(t *testing.T) {
	node, _ := pipeNode(t)
	result := make(chan error, 1)
	go func() { _, err := node.Read(1, 64, 5000); result <- err }()
	if err := node.CloseConnection(1); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-result:
		if err == nil {
			t.Fatal("closed read succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("close did not unblock read")
	}
	if err := node.CloseConnection(1); err != nil {
		t.Fatal(err)
	}
}

func TestClosingOneConnectionPreservesOthers(t *testing.T) {
	node, _ := pipeNode(t)
	local, remote := net.Pipe()
	defer remote.Close()
	node.connections[2] = &connection{conn: local}
	node.CloseConnection(1)
	go remote.Write([]byte("second"))
	data, err := node.Read(2, 64, 1000)
	if err != nil || string(data) != "second" {
		t.Fatalf("second: %q %v", data, err)
	}
}

func TestRejectsInvalidOperations(t *testing.T) {
	node := NewNode()
	if _, err := node.Dial("pc", 0, 1000); err == nil {
		t.Fatal("invalid port accepted")
	}
	if _, err := node.Read(1, 65537, 1000); err == nil {
		t.Fatal("oversized read accepted")
	}
	if _, err := node.Write(1, make([]byte, 65537), 1000); err == nil {
		t.Fatal("oversized write accepted")
	}
	if _, err := node.Status(); err == nil || !strings.Contains(err.Error(), "not started") {
		t.Fatalf("status: %v", err)
	}
	if err := node.WaitReady(1000); err == nil {
		t.Fatal("wait on stopped node succeeded")
	}
}
