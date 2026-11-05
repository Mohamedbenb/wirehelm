package com.example.remote_control.files;

import android.system.Os;
import android.system.StructStat;
import android.system.ErrnoException;
import android.system.OsConstants;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.MessageDigest;
import java.util.*;

/** Invoked via app_process by the app bridge. No exported Android endpoint. */
public final class RootFileWorker {
    private static final int TEXT_LIMIT = 128 * 1024;
    public static void main(String[] args) {
        JSONObject response;
        try {
            if (Os.getuid() != 0) throw new IllegalStateException("Root access was not granted");
            response = execute(new JSONObject(new String(read(System.in, 768 * 1024), StandardCharsets.UTF_8)));
        } catch (Throwable e) {
            response = new JSONObject();
            try { response.put("error", e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()); }
            catch (Exception ignored) {}
        }
        System.out.println(response);
    }
    private static byte[] read(InputStream in, int max) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) != -1) {
            if (out.size() + n > max) throw new IllegalArgumentException("File or request exceeds the size limit");
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }
    private static String hash(byte[] bytes) throws Exception {
        StringBuilder out = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-256").digest(bytes)) out.append(String.format(Locale.ROOT, "%02x", b & 255));
        return out.toString();
    }
    private static JSONObject info(Path p) throws Exception {
        BasicFileAttributes a = Files.readAttributes(p, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        StructStat s = Os.lstat(p.toString());
        return new JSONObject().put("name", p.getFileName() == null ? "/" : p.getFileName().toString())
            .put("path", p.toString()).put("directory", a.isDirectory()).put("link", a.isSymbolicLink())
            .put("regular", a.isRegularFile()).put("size", a.size()).put("modified", a.lastModifiedTime().toMillis())
            .put("mode", Integer.toOctalString(s.st_mode & 07777)).put("uid", s.st_uid).put("gid", s.st_gid)
            .put("identity", s.st_dev + ":" + s.st_ino + ":" + s.st_size + ":" + s.st_mtime + ":" + s.st_ctime);
    }
    private static void identity(Path p, JSONObject q) throws Exception {
        if (!info(p).getString("identity").equals(q.getString("identity")))
            throw new IllegalStateException("This entry changed. Refresh before trying again.");
    }
    private static Path sibling(Path p, String prefix) {
        String n = p.getFileName().toString();
        return p.resolveSibling(prefix + UUID.randomUUID() + "-" + n.substring(0, Math.min(80, n.length())));
    }
    private static byte[] text(Path p) throws Exception {
        if (!Files.isRegularFile(p, LinkOption.NOFOLLOW_LINKS) || Files.size(p) > TEXT_LIMIT)
            throw new IllegalArgumentException("Text preview supports regular UTF-8 files up to 128 KiB");
        try (InputStream in = Files.newInputStream(p, LinkOption.NOFOLLOW_LINKS)) { return read(in, TEXT_LIMIT); }
    }
    private static String decode(byte[] bytes) throws Exception {
        String s = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        if (s.indexOf('\0') >= 0) throw new IllegalArgumentException("Binary files cannot be edited");
        return s;
    }
    static JSONObject execute(JSONObject q) throws Exception {
        String op = q.getString("op");
        Path p = RootFilePolicy.path(q.getString("path"));
        if (op.equals("list")) {
            p = p.toRealPath();
            JSONArray entries = new JSONArray();
            boolean truncated = false;
            try (DirectoryStream<Path> stream = Files.newDirectoryStream(p)) {
                for (Path entry : stream) {
                    if (entries.length() >= 1000) { truncated = true; break; }
                    try { entries.put(info(entry)); }
                    catch (Exception e) { entries.put(new JSONObject().put("name", entry.getFileName().toString()).put("path", entry.toString()).put("error", "Metadata unavailable")); }
                }
            }
            boolean unlockable = true;
            try { RootFilePolicy.scope(p); } catch (Exception e) { unlockable = false; }
            boolean advancedUnlockable = true;
            try { RootFilePolicy.scope(p, true); } catch (Exception e) { advancedUnlockable = false; }
            return new JSONObject().put("path", p.toString()).put("entries", entries)
                .put("truncated", truncated).put("unlockable", unlockable).put("advancedUnlockable", advancedUnlockable).put("scopeIdentity", directoryIdentity(p));
        }
        if (op.equals("read")) {
            JSONObject before = info(p);
            byte[] bytes = text(p);
            if (!info(p).getString("identity").equals(before.getString("identity"))) throw new IllegalStateException("File changed while reading");
            return before.put("text", decode(bytes)).put("hash", hash(bytes));
        }
        String scope = q.getString("scope");
        boolean advanced = q.optBoolean("advanced", false);
        p = RootFilePolicy.writable(p.toString(), scope, advanced);
        if (!directoryIdentity(RootFilePolicy.path(scope)).equals(q.getString("scopeIdentity")))
            throw new IllegalStateException("The unlocked folder was replaced. Lock it and try again.");
        if (op.equals("mkdir")) {
            Files.createDirectory(p);
            try { preserveMetadata(p.getParent(), p); }
            catch (Exception e) { Files.deleteIfExists(p); throw e; }
            return new JSONObject();
        }
        identity(p, q);
        if (op.equals("rename") || op.equals("copy")) {
            Path dest = RootFilePolicy.writable(p.resolveSibling(RootFilePolicy.name(q.getString("name"))).toString(), scope, advanced);
            if (Files.exists(dest, LinkOption.NOFOLLOW_LINKS)) throw new IllegalArgumentException("Destination already exists");
            if (op.equals("rename")) Files.move(p, dest);
            else {
                if (!Files.isRegularFile(p, LinkOption.NOFOLLOW_LINKS) || Files.size(p) > 32L * 1024 * 1024)
                    throw new IllegalArgumentException("Copy supports individual files up to 32 MiB");
                if ((Os.lstat(p.toString()).st_mode & 06000) != 0) throw new IllegalArgumentException("Copying setuid or setgid files is blocked");
                Path temp = RootFilePolicy.customizationPath(p) ? privateBackupPath(q).resolveSibling("writing-" + UUID.randomUUID() + ".tmp") : sibling(dest, ".node-cockpit-writing-");
                try {
                    Files.createFile(temp, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
                    try (InputStream in = Files.newInputStream(p, LinkOption.NOFOLLOW_LINKS); java.io.OutputStream out = Files.newOutputStream(temp)) {
                        byte[] buffer = new byte[8192];
                        int n; long total = 0;
                        while ((n = in.read(buffer)) != -1) {
                            total += n;
                            if (total > 32L * 1024 * 1024) throw new IllegalArgumentException("Copy exceeds 32 MiB");
                            out.write(buffer, 0, n);
                        }
                    }
                    identity(p, q);
                    preserveMetadata(p, temp);
                    Files.move(temp, dest);
                } finally { Files.deleteIfExists(temp); }
            }
            return new JSONObject().put("resultPath", dest.toString());
        }
        if (op.equals("trash")) {
            if (RootFilePolicy.customizationPath(p)) throw new IllegalArgumentException("Trash is disabled in root-manager folders. Use the root manager to disable or remove modules.");
            Path dest = sibling(p, ".node-cockpit-trash-");
            Files.move(p, dest);
            return new JSONObject().put("resultPath", dest.toString());
        }
        if (op.equals("save")) {
            byte[] old = text(p);
            if (!hash(old).equals(q.getString("hash"))) throw new IllegalStateException("File contents changed. Reopen before saving.");
            byte[] replacement = q.getString("text").getBytes(StandardCharsets.UTF_8);
            if (replacement.length > TEXT_LIMIT) throw new IllegalArgumentException("Text exceeds 128 KiB");
            decode(replacement);
            StructStat stat = Os.lstat(p.toString());
            if (stat.st_nlink != 1) throw new IllegalArgumentException("Editing multiply-linked files is blocked; copy to a new file first");
            if ((stat.st_mode & 06000) != 0) throw new IllegalArgumentException("Editing setuid or setgid files is blocked");
            Path backup = RootFilePolicy.customizationPath(p) ? privateBackupPath(q) : sibling(p, ".node-cockpit-backup-");
            Path temp = RootFilePolicy.customizationPath(p) ? backup.resolveSibling("writing-" + UUID.randomUUID() + ".tmp") : sibling(p, ".node-cockpit-writing-");
            try {
                Files.createFile(temp, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
                Files.write(temp, replacement);
                try (java.nio.channels.FileChannel channel = java.nio.channels.FileChannel.open(temp, StandardOpenOption.WRITE)) { channel.force(true); }
                preserveMetadata(p, temp);
                identity(p, q);
                if (!hash(text(p)).equals(q.getString("hash"))) throw new IllegalStateException("File changed before save");
                Files.createFile(backup, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")));
                Files.write(backup, old);
                preserveMetadata(p, backup);
                if (RootFilePolicy.customizationPath(p)) {
                    JSONObject manifest = new JSONObject().put("originalPath", p.toString()).put("created", System.currentTimeMillis()).put("sha256", hash(old));
                    Files.write(backup.resolveSibling(backup.getFileName() + ".json"), manifest.toString().getBytes(StandardCharsets.UTF_8), StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
                }
                try (java.nio.channels.FileChannel channel = java.nio.channels.FileChannel.open(backup, StandardOpenOption.WRITE)) { channel.force(true); }
                identity(p, q);
                if (!hash(text(p)).equals(q.getString("hash"))) throw new IllegalStateException("File changed before replacement");
                Files.move(temp, p, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
                return new JSONObject().put("backup", backup.toString());
            } finally { Files.deleteIfExists(temp); }
        }
        throw new IllegalArgumentException("Unsupported file operation");
    }
    static Path privateBackupPath(JSONObject q) throws Exception {
        Path root = RootFilePolicy.path(q.getString("backupRoot"));
        RootFilePolicy.scope(root);
        if (!root.toRealPath().equals(root) || !Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS))
            throw new IllegalArgumentException("Private backup folder is not canonical");
        StructStat s = Os.lstat(root.toString());
        if (s.st_uid != q.getInt("backupUid") || (s.st_mode & 0777) != 0700)
            throw new IllegalArgumentException("Private backup folder owner or permissions changed");
        return root.resolve("backup-" + UUID.randomUUID() + ".bak");
    }
    private static String directoryIdentity(Path p) throws Exception {
        StructStat s = Os.lstat(p.toString());
        return s.st_dev + ":" + s.st_ino;
    }
    private static byte[] label(Path path) throws Exception {
        try { return Os.getxattr(path.toString(), "security.selinux"); }
        catch (ErrnoException e) {
            if (e.errno == OsConstants.ENODATA || e.errno == OsConstants.EOPNOTSUPP) return null;
            throw e;
        }
    }
    private static void preserveMetadata(Path source, Path dest) throws Exception {
        StructStat s = Os.lstat(source.toString());
        StructStat d = Os.lstat(dest.toString());
        if (d.st_uid != s.st_uid || d.st_gid != s.st_gid) Os.chown(dest.toString(), s.st_uid, s.st_gid);
        if ((d.st_mode & 07777) != (s.st_mode & 07777)) Os.chmod(dest.toString(), s.st_mode & 07777);
        byte[] sourceLabel = label(source);
        if (!Arrays.equals(sourceLabel, label(dest))) {
            if (sourceLabel == null) throw new IllegalStateException("Cannot preserve file security label");
            Os.setxattr(dest.toString(), "security.selinux", sourceLabel, 0);
        }
        d = Os.lstat(dest.toString());
        if (d.st_uid != s.st_uid || d.st_gid != s.st_gid || (d.st_mode & 07777) != (s.st_mode & 07777) || !Arrays.equals(sourceLabel, label(dest)))
            throw new IllegalStateException("Cannot preserve file metadata");
    }
}
