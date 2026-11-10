package com.example.remote_control;

import android.os.IBinder;

/** Invoked by the installed app through its authorized root shell. */
public final class NetworkFirewallWorker {
    public static void main(String[] args) throws Exception {
        if (args.length != 2 || (!"block".equals(args[0]) && !"allow".equals(args[0]))) {
            throw new IllegalArgumentException("Expected a rule and an app UID");
        }
        int uid = Integer.parseInt(args[1]);
        if (uid < 10000 || uid > 19999) {
            throw new IllegalArgumentException("Only owner-profile application UIDs are supported");
        }
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        IBinder binder = (IBinder) serviceManager.getMethod("getService", String.class)
            .invoke(null, "connectivity");
        Class<?> stub = Class.forName("android.net.IConnectivityManager$Stub");
        Object service = stub.getMethod("asInterface", IBinder.class).invoke(null, binder);
        Class<?> api = Class.forName("android.net.IConnectivityManager");
        Class<?> manager = Class.forName("android.net.ConnectivityManager");
        int chain = manager.getField("FIREWALL_CHAIN_OEM_DENY_3").getInt(null);
        int rule = manager.getField("block".equals(args[0]) ? "FIREWALL_RULE_DENY" : "FIREWALL_RULE_DEFAULT")
            .getInt(null);
        api.getMethod("setUidFirewallRule", int.class, int.class, int.class)
            .invoke(service, chain, uid, rule);
    }
}
