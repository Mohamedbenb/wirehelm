package tsnetbridge

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/netip"
	"strconv"
	"sync"
	"time"
)

const debugRelayPort = 5555
const defaultDebugRelayMinutes = 30

// A single opt-in, expiring tailnet listener. Local targets are always loopback;
// there is no LAN listener, command execution, or generic port-forward API.
type debugRelay struct {
	mu              sync.Mutex
	listener        net.Listener
	allowed         netip.Addr
	localPort       int
	expires         time.Time
	durationMinutes int
	expiryChanged   chan struct{}
	stopped         bool
	sockets         map[net.Conn]bool
	active          int
	lastError       string
	cancel          context.CancelFunc
}

func debugPeer(raw string) (netip.Addr, error) {
	ip, err := netip.ParseAddr(raw)
	if err != nil {
		return netip.Addr{}, errors.New("select a Tailscale IP for the permitted PC")
	}
	ip = ip.Unmap()
	if !netip.MustParsePrefix("100.64.0.0/10").Contains(ip) && !netip.MustParsePrefix("fd7a:115c:a1e0::/48").Contains(ip) {
		return netip.Addr{}, errors.New("permitted PC must use a Tailscale address")
	}
	return ip, nil
}

func debugLifetime(minutes int) (time.Duration, error) {
	if minutes < 5 || minutes > 1440 {
		return 0, errors.New("session duration must be 5..1440 minutes")
	}
	return time.Duration(minutes) * time.Minute, nil
}

// Retain the original default API for existing callers.
func (n *Node) StartDebugRelay(localPort int, allowedPC string) error {
	return n.StartDebugRelayWithDuration(localPort, allowedPC, defaultDebugRelayMinutes)
}
func (n *Node) StartDebugRelayWithDuration(localPort int, allowedPC string, minutes int) error {
	lifetime, err := debugLifetime(minutes)
	if err != nil {
		return err
	}
	if localPort < 1 || localPort > 65535 {
		return errors.New("invalid local ADB port")
	}
	peer, err := debugPeer(allowedPC)
	if err != nil {
		return err
	}
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	server, root, err := n.current()
	if err != nil {
		return err
	}
	n.stopDebugRelay()
	listener, err := server.Listen("tcp", ":"+strconv.Itoa(debugRelayPort))
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(root)
	relay := &debugRelay{listener: listener, allowed: peer, localPort: localPort,
		expires: time.Now().Add(lifetime), durationMinutes: minutes, expiryChanged: make(chan struct{}, 1), sockets: make(map[net.Conn]bool), cancel: cancel}
	n.mu.Lock()
	n.debug = relay
	n.mu.Unlock()
	go relay.serve(ctx)
	return nil
}

// Reset the active deadline from now without closing listener or streams.
func (n *Node) SetDebugRelayDuration(minutes int) error {
	lifetime, err := debugLifetime(minutes)
	if err != nil {
		return err
	}
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	n.mu.Lock()
	relay := n.debug
	n.mu.Unlock()
	if relay == nil {
		return errors.New("debug relay is not running")
	}
	relay.mu.Lock()
	if relay.stopped {
		relay.mu.Unlock()
		return errors.New("debug relay has expired")
	}
	relay.expires = time.Now().Add(lifetime)
	relay.durationMinutes = minutes
	relay.mu.Unlock()
	select {
	case relay.expiryChanged <- struct{}{}:
	default:
	}
	return nil
}

func (n *Node) StopDebugRelay() {
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	n.stopDebugRelay()
}
func (n *Node) stopDebugRelay() {
	n.mu.Lock()
	relay := n.debug
	n.debug = nil
	n.mu.Unlock()
	if relay != nil {
		relay.close()
	}
}
func (n *Node) DebugRelayStatus() string {
	n.mu.Lock()
	relay := n.debug
	n.mu.Unlock()
	state := map[string]any{"enabled": false, "remotePort": debugRelayPort}
	if relay != nil {
		relay.mu.Lock()
		state = map[string]any{"enabled": !relay.stopped, "allowedPC": relay.allowed.String(),
			"remotePort": debugRelayPort, "localPort": relay.localPort, "expiresAt": relay.expires.UnixMilli(), "durationMinutes": relay.durationMinutes,
			"connections": relay.active, "lastError": relay.lastError}
		relay.mu.Unlock()
	}
	data, _ := json.Marshal(state)
	return string(data)
}
func (r *debugRelay) close() {
	r.mu.Lock()
	if r.stopped {
		r.mu.Unlock()
		return
	}
	r.stopped = true
	r.cancel()
	r.listener.Close()
	for conn := range r.sockets {
		conn.Close()
	}
	r.mu.Unlock()
}
func (r *debugRelay) serve(ctx context.Context) {
	r.mu.Lock()
	deadline := r.expires
	r.mu.Unlock()
	go func() {
		timer := time.NewTimer(time.Until(deadline))
		defer timer.Stop()
		for {
			select {
			case <-ctx.Done():
				r.close()
				return
			case <-r.expiryChanged:
			case <-timer.C:
			}
			r.mu.Lock()
			remaining := time.Until(r.expires)
			if r.stopped {
				r.mu.Unlock()
				return
			}
			if remaining <= 0 {
				// Linearize expiry with a concurrent deadline update.
				r.stopped = true
				r.cancel()
				r.listener.Close()
				for conn := range r.sockets {
					conn.Close()
				}
				r.mu.Unlock()
				return
			}
			r.mu.Unlock()
			timer.Reset(remaining)
		}
	}()
	defer r.close()
	for {
		incoming, err := r.listener.Accept()
		if err != nil {
			return
		}
		host, _, err := net.SplitHostPort(incoming.RemoteAddr().String())
		peer, parseErr := netip.ParseAddr(host)
		if err != nil || parseErr != nil || peer.Unmap() != r.allowed {
			incoming.Close()
			continue
		}
		r.mu.Lock()
		if r.stopped || r.active >= 4 {
			r.mu.Unlock()
			incoming.Close()
			continue
		}
		r.active++
		r.sockets[incoming] = true
		r.mu.Unlock()
		go r.forward(ctx, incoming)
	}
}
func (r *debugRelay) forward(ctx context.Context, incoming net.Conn) {
	defer func() { incoming.Close(); r.mu.Lock(); delete(r.sockets, incoming); r.active--; r.mu.Unlock() }()
	local, err := (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, "tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(r.localPort)))
	if err != nil {
		r.mu.Lock()
		r.lastError = "Local ADB listener unavailable; refresh or restart the session"
		r.mu.Unlock()
		return
	}
	r.mu.Lock()
	if r.stopped {
		r.mu.Unlock()
		local.Close()
		return
	}
	r.sockets[local] = true
	r.lastError = ""
	r.mu.Unlock()
	defer func() { local.Close(); r.mu.Lock(); delete(r.sockets, local); r.mu.Unlock() }()
	done := make(chan struct{}, 1)
	go func() { io.Copy(local, incoming); done <- struct{}{} }()
	io.Copy(incoming, local)
	local.Close()
	incoming.Close()
	<-done
}
