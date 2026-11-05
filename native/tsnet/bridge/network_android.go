//go:build android

package tsnetbridge

import "tailscale.com/net/netmon"

func platformNetworkChanged(name, gateway string) {
	netmon.UpdateLastKnownDefaultRouteInterface(name)
	netmon.UpdateLastKnownDefaultGateway(gateway)
}
