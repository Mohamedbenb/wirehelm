package com.example.remote_control.files;

import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;

/** Enforced again in the short-lived root worker, not just by the UI. */
public final class RootFilePolicy {
    private RootFilePolicy() {}
    private static final String[] BLOCKED = {
        "/system", "/system_ext", "/vendor", "/product", "/odm", "/oem", "/apex",
        "/dev", "/proc", "/sys", "/config", "/acct", "/metadata", "/mnt", "/persist", "/efs",
        "/bootstrap-apex", "/debug_ramdisk", "/linkerconfig", "/data_mirror",
        "/data/adb", "/data/app", "/data/system", "/data/system_de", "/data/system_ce",
        "/data/misc", "/data/misc_de", "/data/misc_ce", "/data/vendor",
        "/data/property", "/data/resource-cache", "/data/dalvik-cache", "/data/unencrypted"
    };
    public static Path path(String value) {
        if (value == null || value.indexOf('\0') >= 0 || value.length() > 4096 || !value.startsWith("/"))
            throw new IllegalArgumentException("An absolute path is required");
        return Paths.get(value).normalize();
    }
    public static boolean protectedPath(Path path) {
        String p = path.normalize().toString();
        for (String prefix : BLOCKED) if (p.equals(prefix) || p.startsWith(prefix + "/")) return true;
        return false;
    }
    public static boolean customizationPath(Path path) {
        String p = path.normalize().toString();
        return p.equals("/data/adb") || p.startsWith("/data/adb/");
    }
    private static boolean writeProtected(Path path, boolean advanced) {
        // Explicit user-authorized customization exception, limited to /data/adb.
        // Normal unlock and all other critical paths retain the existing policy.
        return protectedPath(path) && !(advanced && customizationPath(path));
    }
    public static void scope(Path root) {
        scope(root, false);
    }
    public static void scope(Path root, boolean advanced) {
        String p = root.toString();
        boolean userFolder = p.matches("/data/user(_de)?/[0-9]+/[^/]+(/.*)?") || p.matches("/data/data/[^/]+(/.*)?");
        boolean sharedFolder = p.matches("/data/media/[0-9]+(/.*)?") || p.matches("/storage/emulated/[0-9]+(/.*)?") || p.matches("/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}(/.*)?");
        boolean tempFolder = p.equals("/data/local/tmp") || p.startsWith("/data/local/tmp/");
        if ((!advanced && !userFolder && !sharedFolder && !tempFolder) || !root.isAbsolute() || root.getNameCount() < 2 || writeProtected(root, advanced)
                || root.toString().equals("/data/media") || root.toString().equals("/data/user")
                || root.toString().equals("/data/user_de") || p.equals("/data/data") || p.equals("/storage/emulated")
                || root.toString().matches("/data/user(_de)?/[0-9]+"))
            throw new IllegalArgumentException("Choose a specific writable folder. This location is protected.");
    }
    public static void confirmation(Path root, String typed) {
        if (!root.toString().equals(typed))
            throw new IllegalArgumentException("Type the complete folder path to confirm advanced access");
    }
    public static Path writable(String value, String scope) throws Exception {
        return writable(value, scope, false);
    }
    public static Path writable(String value, String scope, boolean advanced) throws Exception {
        Path root = path(scope);
        scope(root, advanced);
        Path target = path(value);
        if (!target.startsWith(root) || target.equals(root) || writeProtected(target, advanced))
            throw new IllegalArgumentException("Writes are limited to children of the unlocked folder");
        Path part = target.getRoot();
        for (Path name : target) {
            part = part.resolve(name);
            if (Files.isSymbolicLink(part)) throw new IllegalArgumentException("Writing through symbolic links is blocked");
        }
        if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS) || !root.toRealPath().equals(root))
            throw new IllegalArgumentException("The unlocked folder changed; lock it and try again");
        if (!Files.isDirectory(target.getParent(), LinkOption.NOFOLLOW_LINKS))
            throw new IllegalArgumentException("Parent folder is unavailable");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)
                && !Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)
                && !Files.isDirectory(target, LinkOption.NOFOLLOW_LINKS))
            throw new IllegalArgumentException("Writing special filesystem entries is blocked");
        return target;
    }
    public static String name(String name) {
        if (name == null || name.isEmpty() || name.equals(".") || name.equals("..")
                || name.contains("/") || name.indexOf('\0') >= 0 || name.length() > 240)
            throw new IllegalArgumentException("Enter a single file or folder name");
        return name;
    }
}
