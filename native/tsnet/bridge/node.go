// Package tsnetbridge exposes a small, gomobile-compatible tsnet byte transport.
package tsnetbridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"strconv"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

type connection struct {
	conn    net.Conn
	readMu  sync.Mutex
	writeMu sync.Mutex
}

// Node owns one persistent tailnet identity and independent TCP connections.
// Call CloseConnection for one SSH session; Close stops the entire node.
type Node struct {
	lifecycle   sync.Mutex
	mu          sync.Mutex
	server      *tsnet.Server
	ctx         context.Context
	cancel      context.CancelFunc
	dir         string
	nextID      int64
	connections map[int64]*connection
	debug       *debugRelay
}

func NewNode() *Node { return &Node{connections: make(map[int64]*connection)} }

func (n *Node) Start(dir, hostname, authKey string) error {
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	if dir == "" || hostname == "" {
		return errors.New("state directory and hostname are required")
	}
	n.mu.Lock()
	if n.server != nil {
		same := n.dir == dir
		n.mu.Unlock()
		if !same {
			return errors.New("node already started with another identity directory")
		}
		return nil
	}
	n.mu.Unlock()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	// Android app processes have no HOME or writable current directory.
	// Tailscale's socket statistics logger also needs an explicit private path.
	if runtime.GOOS == "android" {
		if err := os.Setenv("TS_LOGS_DIR", dir); err != nil {
			return err
		}
	}
	server := &tsnet.Server{Dir: dir, Hostname: hostname, AuthKey: authKey,
		Logf: func(string, ...any) {}, UserLogf: func(string, ...any) {}}
	if err := server.Start(); err != nil {
		server.Close()
		return err
	}
	n.mu.Lock()
	n.server = server
	n.dir = dir
	n.ctx, n.cancel = context.WithCancel(context.Background())
	n.mu.Unlock()
	return nil
}

func (n *Node) current() (*tsnet.Server, context.Context, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.server == nil {
		return nil, nil, errors.New("tsnet is not started")
	}
	return n.server, n.ctx, nil
}

func duration(milliseconds int64) (time.Duration, error) {
	if milliseconds < 1 || milliseconds > 300000 {
		return 0, errors.New("timeout must be 1..300000 milliseconds")
	}
	return time.Duration(milliseconds) * time.Millisecond, nil
}

// Wait waits for tailnet readiness, bounded by the supplied timeout.
func (n *Node) WaitReady(timeoutMilliseconds int64) error {
	server, root, err := n.current()
	if err != nil {
		return err
	}
	timeout, err := duration(timeoutMilliseconds)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(root, timeout)
	defer cancel()
	_, err = server.Up(ctx)
	return err
}

// Status returns only connection state, login URL, and this node's addresses.
// Peers returns the tailnet nodes visible to this app's identity. Online is
// control-plane state, not proof that SSH is reachable.
func (n *Node) Peers() (string, error) {
	server, root, err := n.current()
	if err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(root, 5*time.Second)
	defer cancel()
	client, err := server.LocalClient()
	if err != nil {
		return "", err
	}
	status, err := client.Status(ctx)
	if err != nil {
		return "", err
	}
	peers := make([]map[string]any, 0, len(status.Peer))
	for _, peer := range status.Peer {
		ips := make([]string, 0, len(peer.TailscaleIPs))
		for _, ip := range peer.TailscaleIPs {
			ips = append(ips, ip.String())
		}
		lastSeen := ""
		if !peer.LastSeen.IsZero() {
			lastSeen = peer.LastSeen.UTC().Format(time.RFC3339)
		}
		peers = append(peers, map[string]any{"id": string(peer.ID), "name": peer.HostName, "dnsName": peer.DNSName, "os": peer.OS, "ips": ips, "online": peer.Online, "lastSeen": lastSeen, "exitNode": peer.ExitNodeOption, "directAddress": peer.CurAddr, "relay": peer.Relay, "active": peer.Active, "rxBytes": peer.RxBytes, "txBytes": peer.TxBytes})
	}
	data, err := json.Marshal(peers)
	return string(data), err
}

func (n *Node) Status() (string, error) {
	server, root, err := n.current()
	if err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(root, 5*time.Second)
	defer cancel()
	client, err := server.LocalClient()
	if err != nil {
		return "", err
	}
	status, err := client.Status(ctx)
	if err != nil {
		return "", err
	}
	result := struct {
		State   string   `json:"state"`
		AuthURL string   `json:"authUrl"`
		IPs     []string `json:"ips"`
	}{State: status.BackendState, AuthURL: status.AuthURL, IPs: []string{}}
	for _, ip := range status.TailscaleIPs {
		result.IPs = append(result.IPs, ip.String())
	}
	data, err := json.Marshal(result)
	return string(data), err
}

func (n *Node) Dial(host string, port int, timeoutMilliseconds int64) (int64, error) {
	if host == "" || port < 1 || port > 65535 {
		return 0, errors.New("invalid host or port")
	}
	timeout, err := duration(timeoutMilliseconds)
	if err != nil {
		return 0, err
	}
	server, root, err := n.current()
	if err != nil {
		return 0, err
	}
	ctx, cancel := context.WithTimeout(root, timeout)
	defer cancel()
	conn, err := server.Dial(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		return 0, err
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.server != server {
		conn.Close()
		return 0, errors.New("node closed during dial")
	}
	n.nextID++
	n.connections[n.nextID] = &connection{conn: conn}
	return n.nextID, nil
}

func (n *Node) lookup(id int64) (*connection, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	conn := n.connections[id]
	if conn == nil {
		return nil, errors.New("connection is closed")
	}
	return conn, nil
}

// Read returns empty bytes at EOF. Read deadlines use the stable error token
// TSNET_READ_TIMEOUT, which allows Flutter to retry without treating it as EOF.
func (n *Node) Read(id int64, maxBytes int, timeoutMilliseconds int64) ([]byte, error) {
	if maxBytes < 1 || maxBytes > 65536 {
		return nil, errors.New("read size must be 1..65536 bytes")
	}
	timeout, err := duration(timeoutMilliseconds)
	if err != nil {
		return nil, err
	}
	conn, err := n.lookup(id)
	if err != nil {
		return nil, err
	}
	conn.readMu.Lock()
	defer conn.readMu.Unlock()
	if err := conn.conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return nil, err
	}
	buffer := make([]byte, maxBytes)
	count, err := conn.conn.Read(buffer)
	if count > 0 {
		return buffer[:count], nil
	}
	if errors.Is(err, io.EOF) {
		return []byte{}, nil
	}
	if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
		return nil, errors.New("TSNET_READ_TIMEOUT")
	}
	return nil, err
}

// Write serializes writes and sends every byte, including partial net.Conn writes.
func (n *Node) Write(id int64, data []byte, timeoutMilliseconds int64) (int, error) {
	if len(data) > 65536 {
		return 0, errors.New("write size must not exceed 65536 bytes")
	}
	timeout, err := duration(timeoutMilliseconds)
	if err != nil {
		return 0, err
	}
	conn, err := n.lookup(id)
	if err != nil {
		return 0, err
	}
	conn.writeMu.Lock()
	defer conn.writeMu.Unlock()
	if err := conn.conn.SetWriteDeadline(time.Now().Add(timeout)); err != nil {
		return 0, err
	}
	total := 0
	for total < len(data) {
		count, err := conn.conn.Write(data[total:])
		total += count
		if err != nil {
			return total, fmt.Errorf("write: %w", err)
		}
		if count == 0 {
			return total, io.ErrShortWrite
		}
	}
	return total, nil
}

func (n *Node) CloseConnection(id int64) error {
	n.mu.Lock()
	conn := n.connections[id]
	delete(n.connections, id)
	n.mu.Unlock()
	if conn == nil {
		return nil
	}
	return conn.conn.Close()
}

func (n *Node) Close() error {
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	n.stopDebugRelay()
	n.mu.Lock()
	server := n.server
	n.server = nil
	if n.cancel != nil {
		n.cancel()
	}
	connections := n.connections
	n.connections = make(map[int64]*connection)
	n.mu.Unlock()
	for _, conn := range connections {
		conn.conn.Close()
	}
	if server != nil {
		return server.Close()
	}
	return nil
}
