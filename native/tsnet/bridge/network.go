package tsnetbridge

import (
	"encoding/json"
	"net"
	"runtime"
	"sync"

	"tailscale.com/net/netmon"
)

var networkState struct {
	sync.RWMutex
	interfaces []netmon.Interface
}

func init() {
	if runtime.GOOS == "android" {
		netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) {
			networkState.RLock()
			defer networkState.RUnlock()
			return append([]netmon.Interface(nil), networkState.interfaces...), nil
		})
	}
}

// UpdateNetwork receives app-visible interfaces from Android's ConnectivityManager.
// Android app UIDs cannot rely on Go's net.Interfaces/netlink enumeration.
func (n *Node) UpdateNetwork(snapshot string) error {
	var data struct {
		DefaultInterface string `json:"defaultInterface"`
		Gateway          string `json:"gateway"`
		Interfaces       []struct {
			Name      string   `json:"name"`
			Index     int      `json:"index"`
			MTU       int      `json:"mtu"`
			Addresses []string `json:"addresses"`
		} `json:"interfaces"`
	}
	if err := json.Unmarshal([]byte(snapshot), &data); err != nil {
		return err
	}
	interfaces := []netmon.Interface{{Interface: &net.Interface{
		Name: "lo", Index: 1, MTU: 65536, Flags: net.FlagUp | net.FlagRunning | net.FlagLoopback,
	}, AltAddrs: []net.Addr{&net.IPNet{IP: net.IPv4(127, 0, 0, 1), Mask: net.CIDRMask(8, 32)}}}}
	for _, source := range data.Interfaces {
		addresses := []net.Addr{}
		for _, value := range source.Addresses {
			ip, prefix, err := net.ParseCIDR(value)
			if err != nil {
				return err
			}
			prefix.IP = ip
			addresses = append(addresses, prefix)
		}
		interfaces = append(interfaces, netmon.Interface{
			Interface: &net.Interface{Name: source.Name, Index: source.Index, MTU: source.MTU,
				Flags: net.FlagUp | net.FlagRunning | net.FlagMulticast}, AltAddrs: addresses,
		})
	}
	networkState.Lock()
	networkState.interfaces = interfaces
	networkState.Unlock()
	platformNetworkChanged(data.DefaultInterface, data.Gateway)
	n.mu.Lock()
	server := n.server
	n.mu.Unlock()
	if server != nil {
		server.Sys().NetMon.Get().InjectEvent()
	}
	return nil
}
