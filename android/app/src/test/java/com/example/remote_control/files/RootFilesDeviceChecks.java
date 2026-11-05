package com.example.remote_control.files;

import android.system.Os;
import org.json.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Run as root with app_process, only in its own randomly named /data/local/tmp tree. */
public final class RootFilesDeviceChecks {
    interface Check { void run() throws Exception; }
    private static final JSONArray passed = new JSONArray();
    private static void ok(boolean value) { if (!value) throw new AssertionError("Check failed"); }
    private static void test(String name, Check action) throws Exception { action.run(); passed.put(name); }
    private static void rejects(Check action) throws Exception {
        boolean rejected = false;
        try { action.run(); } catch (Exception e) { rejected = true; }
        ok(rejected);
    }
    private static JSONObject call(String op, Path p) throws Exception { return RootFileWorker.execute(new JSONObject().put("op", op).put("path", p.toString())); }
    private static JSONObject write(String op, Path p, Path root) throws Exception {
        JSONObject q = new JSONObject().put("op", op).put("path", p.toString()).put("scope", root.toString())
            .put("scopeIdentity", call("list", root).getString("scopeIdentity"));
        if (Files.isRegularFile(p, LinkOption.NOFOLLOW_LINKS)) q.put("identity", call("read", p).getString("identity"));
        return q;
    }
    public static void main(String[] args) throws Exception {
        if (Os.getuid() != 0) throw new AssertionError("Root required");
        Path root = Paths.get("/data/local/tmp/node-cockpit-file-check-" + UUID.randomUUID());
        Files.createDirectory(root);
        try {
            Path file = root.resolve("quote' $() café.txt");
            Files.write(file, "Original café\n".getBytes(StandardCharsets.UTF_8));
            test("read UTF-8 and shell metacharacters literally", () -> ok(call("read", file).getString("text").equals("Original café\n")));
            test("list returns canonical path and metadata", () -> { JSONObject r = call("list", root); ok(r.getString("path").equals(root.toString()) && r.getJSONArray("entries").length() == 1); });
            test("write without an unlock scope refused", () -> rejects(() -> call("mkdir", root.resolve("no-scope"))));
            test("path traversal outside scope refused", () -> rejects(() -> RootFilePolicy.writable(root.resolve("../../escape").toString(), root.toString())));
            test("prefix sibling escape refused", () -> rejects(() -> RootFilePolicy.writable(root + "-sibling/file", root.toString())));
            test("scope itself cannot be mutated", () -> rejects(() -> RootFilePolicy.writable(root.toString(), root.toString())));
            test("critical scopes refused", () -> { for (String p : new String[]{"/", "/data", "/data/user/0", "/system/x", "/dev/block", "/proc/sys", "/data/adb/modules", "/data/system/users", "/data/app/test", "/apex/foo", "/metadata/test"}) rejects(() -> RootFilePolicy.scope(RootFilePolicy.path(p))); });
            test("supported canonical storage scopes", () -> { for (String p : new String[]{"/data/data/com.example.test", "/data/user/0/com.example.test", "/data/media/0", "/storage/emulated/0", "/data/local/tmp"}) RootFilePolicy.scope(RootFilePolicy.path(p)); });
            test("advanced allows ordinary folders outside default list", () -> {
                rejects(() -> RootFilePolicy.scope(Paths.get("/data/local")));
                RootFilePolicy.scope(Paths.get("/data/local"), true);
                RootFilePolicy.scope(Paths.get("/cache/ordinary"), true);
                JSONObject q = write("mkdir", root.resolve("advanced-child"), Paths.get("/data/local"));
                rejects(() -> RootFileWorker.execute(q));
                RootFileWorker.execute(q.put("advanced", true));
                ok(Files.isDirectory(root.resolve("advanced-child")));
            });
            test("advanced still rejects unrelated critical and broad scopes", () -> { for (String p : new String[]{"/", "/data", "/data/user/0", "/system/etc", "/vendor/etc", "/data/system/users", "/data/app/pkg", "/proc/sys", "/sys/kernel", "/dev/block", "/config/test", "/apex/test", "/metadata/test", "/data_mirror/test"}) rejects(() -> RootFilePolicy.scope(Paths.get(p), true)); });
            test("data adb exception is advanced-only and path-bounded", () -> {
                for (String p : new String[]{"/data/adb", "/data/adb/modules/example", "/data/adb/service.d"}) {
                    rejects(() -> RootFilePolicy.scope(Paths.get(p)));
                    RootFilePolicy.scope(Paths.get(p), true);
                    ok(RootFilePolicy.customizationPath(Paths.get(p)));
                }
                ok(!RootFilePolicy.customizationPath(Paths.get("/data/adb_backup")));
                ok(!RootFilePolicy.customizationPath(RootFilePolicy.path("/data/adb/../system")));
                rejects(() -> RootFilePolicy.scope(RootFilePolicy.path("/data/adb/../system"), true));
                rejects(() -> RootFilePolicy.writable("/data/system/outside", "/data/adb", true));
            });
            test("advanced confirmation must exactly match canonical path", () -> { RootFilePolicy.confirmation(root, root.toString()); rejects(() -> RootFilePolicy.confirmation(root, "")); rejects(() -> RootFilePolicy.confirmation(root, root + "/")); });
            test("private backup destination checks ownership mode and canonical path", () -> {
                Path backups = root.resolve("private-backups");
                Files.createDirectory(backups, java.nio.file.attribute.PosixFilePermissions.asFileAttribute(java.nio.file.attribute.PosixFilePermissions.fromString("rwx------")));
                JSONObject q = new JSONObject().put("backupRoot", backups.toString()).put("backupUid", Os.getuid());
                ok(RootFileWorker.privateBackupPath(q).getParent().equals(backups));
                rejects(() -> RootFileWorker.privateBackupPath(new JSONObject(q.toString()).put("backupUid", Os.getuid() + 1)));
                Os.chmod(backups.toString(), 0755);
                rejects(() -> RootFileWorker.privateBackupPath(q));
                Os.chmod(backups.toString(), 0700);
                Path alias = root.resolve("backup-alias"); Files.createSymbolicLink(alias, backups);
                rejects(() -> RootFileWorker.privateBackupPath(new JSONObject(q.toString()).put("backupRoot", alias.toString())));
                rejects(() -> RootFileWorker.privateBackupPath(new JSONObject(q.toString()).put("backupRoot", "/data/adb")));
            });
            test("advanced retains symlink and scope escape protections", () -> { rejects(() -> RootFilePolicy.writable(root + "/../../escape", root.toString(), true)); });
            test("mkdir inside scope", () -> { RootFileWorker.execute(write("mkdir", root.resolve("folder"), root)); ok(Files.isDirectory(root.resolve("folder"))); });
            Path link = root.resolve("link");
            Files.createSymbolicLink(link, root.resolve("folder"));
            test("symbolic link ancestor refused", () -> { rejects(() -> RootFilePolicy.writable(link.resolve("child").toString(), root.toString())); rejects(() -> RootFilePolicy.writable(link.resolve("child").toString(), root.toString(), true)); });
            test("symbolic link leaf refused", () -> rejects(() -> RootFilePolicy.writable(link.toString(), root.toString())));
            test("copy keeps source and creates destination", () -> { RootFileWorker.execute(write("copy", file, root).put("name", "copy.txt")); ok(Files.exists(file) && Arrays.equals(Files.readAllBytes(file), Files.readAllBytes(root.resolve("copy.txt")))); });
            test("copy never overwrites", () -> rejects(() -> RootFileWorker.execute(write("copy", file, root).put("name", "copy.txt"))));
            test("rename rejects nested destination", () -> rejects(() -> RootFileWorker.execute(write("rename", file, root).put("name", "folder/escape"))));
            test("save retains original backup and metadata", () -> {
                JSONObject before = call("read", file);
                JSONObject result = RootFileWorker.execute(write("save", file, root).put("hash", before.getString("hash")).put("text", "Changed\n"));
                ok(new String(Files.readAllBytes(Paths.get(result.getString("backup"))), StandardCharsets.UTF_8).equals("Original café\n"));
                JSONObject after = call("read", file);
                ok(after.getString("text").equals("Changed\n") && after.getString("mode").equals(before.getString("mode")) && after.getInt("uid") == before.getInt("uid"));
            });
            test("stale content hash refuses save", () -> { JSONObject q = write("save", file, root).put("hash", "wrong").put("text", "Bad"); rejects(() -> RootFileWorker.execute(q)); ok(call("read", file).getString("text").equals("Changed\n")); });
            test("stale inode refuses rename", () -> { JSONObject q = write("rename", file, root).put("name", "bad.txt"); Files.delete(file); Files.write(file, "replacement".getBytes(StandardCharsets.UTF_8)); rejects(() -> RootFileWorker.execute(q)); });
            test("binary preview refused", () -> { Path binary = root.resolve("binary"); Files.write(binary, new byte[]{0, 1, 2}); rejects(() -> call("read", binary)); });
            test("oversize preview refused", () -> { Path large = root.resolve("large"); Files.write(large, new byte[128 * 1024 + 1]); rejects(() -> call("read", large)); });
            test("trash is reversible and retains original bytes", () -> { JSONObject q = write("trash", file, root); JSONObject r = RootFileWorker.execute(q); Path trash = Paths.get(r.getString("resultPath")); ok(!Files.exists(file) && Files.exists(trash)); RootFileWorker.execute(write("rename", trash, root).put("name", file.getFileName().toString())); ok(call("read", file).getString("text").equals("replacement")); });
            test("replaced unlock folder refused", () -> { Path lease = root.resolve("lease"); Files.createDirectory(lease); JSONObject q = write("mkdir", lease.resolve("child"), lease); Files.move(lease, root.resolve("lease-old")); Files.createDirectory(lease); rejects(() -> RootFileWorker.execute(q)); });
            test("unsupported operations refused", () -> rejects(() -> RootFileWorker.execute(write("chmod", file, root))));
            System.out.println(new JSONObject().put("passed", passed.length()).put("checks", passed));
        } finally {
            // This exact fresh UUID tree is the only deletion target; links are never followed.
            if (!root.toString().startsWith("/data/local/tmp/node-cockpit-file-check-")) throw new AssertionError();
            try (java.util.stream.Stream<Path> paths = Files.walk(root)) {
                for (Path p : (Iterable<Path>) paths.sorted(Comparator.reverseOrder())::iterator) Files.delete(p);
            }
        }
    }
}
