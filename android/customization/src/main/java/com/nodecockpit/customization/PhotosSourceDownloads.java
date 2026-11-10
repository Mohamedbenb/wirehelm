package com.nodecockpit.customization;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.CancellationSignal;
import android.os.OperationCanceledException;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/** One sequential transfer at a time. The journal records the MediaStore row before writing bytes. */
final class PhotosSourceDownloads {
    private static final String TAG = "WirehelmCloudCamera";
    private final Context context;
    private final CloudCameraMedia media;
    private final SharedPreferences journal;

    record Progress(int done, int skipped, int total, boolean stopped, String problem) {
        boolean finished() { return done + skipped == total; }
    }

    static final class Job {
        final String name;
        final PhotosMediaFolders.Folder folder;
        final List<String> keys;
        int next;
        int skipped;
        Uri pending;

        Job(String name, PhotosMediaFolders.Folder folder, List<String> keys) {
            this.name = name;
            this.folder = folder;
            this.keys = List.copyOf(keys);
        }

        Progress progress(boolean stopped, String problem) {
            return new Progress(next - skipped, skipped, keys.size(), stopped, problem);
        }
    }

    PhotosSourceDownloads(Context context, CloudCameraMedia media) {
        this.context = context;
        this.media = media;
        journal = context.getSharedPreferences("wirehelm_photos_downloads", Context.MODE_PRIVATE);
    }

    Job saved(int account) throws JSONException {
        String value = journal.getString(key(account), null);
        if (value == null) return null;
        JSONObject json = new JSONObject(value);
        var folder = new PhotosMediaFolders.Folder(json.getString("volume"), json.getString("path"),
                uri(json, "image"), uri(json, "video"));
        JSONArray entries = json.getJSONArray("keys");
        List<String> keys = new ArrayList<>(entries.length());
        for (int i = 0; i < entries.length(); i++) keys.add(entries.getString(i));
        Job job = new Job(json.getString("name"), folder, keys);
        job.next = json.getInt("next");
        job.skipped = json.getInt("skipped");
        job.pending = uri(json, "pending");
        return job;
    }

    void run(int account, Job job, CancellationSignal signal, boolean skipCurrent,
             Consumer<Progress> listener) {
        String problem = null;
        try {
            save(account, job);
            signal.throwIfCanceled();
            if (skipCurrent && job.next < job.keys.size()) {
                int state = job.pending == null ? -1
                        : PhotosMediaFolders.pendingState(context.getContentResolver(), job.pending);
                if (state == 1) discard(job);
                advance(account, job, state != 0);
            }
            while (job.next < job.keys.size()) {
                signal.throwIfCanceled();
                listener.accept(job.progress(false, null));
                download(account, job, signal);
            }
            if (!journal.edit().remove(key(account)).commit()) throw new IOException("Could not finish journal");
        } catch (OperationCanceledException canceled) {
            // Keep the unfinished row in the journal. A retry truncates it before writing again.
        } catch (IOException | JSONException | ReflectiveOperationException | RuntimeException | LinkageError error) {
            Throwable cause = error.getCause() == null ? error : error.getCause();
            Log.w(TAG, "Source download paused (" + cause.getClass().getSimpleName() + ")");
            problem = error instanceof DownloadFailure ? error.getMessage()
                    : "The file could not be saved. You can retry or skip it.";
        } finally {
            listener.accept(job.progress(true, problem));
        }
    }

    private void download(int account, Job job, CancellationSignal signal)
            throws IOException, ReflectiveOperationException, JSONException {
        var resolver = context.getContentResolver();
        if (job.pending != null) {
            int state = PhotosMediaFolders.pendingState(resolver, job.pending);
            if (state == 0) {
                // Publication succeeded before a process restart or a failed journal update.
                advance(account, job, false);
                return;
            }
            if (state < 0) job.pending = null;
        }
        String key = job.keys.get(job.next);
        CloudCameraIndex.Download item = CloudCameraIndex.download(
                context.getDatabasePath("gphotos" + account + ".db"), key, signal);
        if (item == null || item.local()) {
            discard(job);
            advance(account, job, true);
            return;
        }
        if (item.name() == null || item.name().isBlank() || item.size() <= 0 || item.mime() == null
                || !(item.mime().startsWith("image/") || item.mime().startsWith("video/"))) {
            throw new DownloadFailure("Photos did not provide the file metadata needed to verify this download.");
        }
        Uri original = media.originalUri(context, account, key, signal);
        if (original == null) throw new DownloadFailure("Photos did not provide an original for this item.");
        if (job.pending == null) {
            job.pending = PhotosMediaFolders.reserve(resolver, job.folder, item);
            try {
                save(account, job);
            } catch (IOException | JSONException error) {
                discard(job);
                throw error;
            }
        }
        try {
            PhotosMediaFolders.transfer(resolver, original, job.pending, item.size(), signal);
        } catch (IOException error) {
            if (signal.isCanceled()) throw new OperationCanceledException();
            throw new DownloadFailure("Photos could not supply the expected original file.", error);
        }
        signal.throwIfCanceled();
        PhotosMediaFolders.publish(resolver, job.pending, item.dateTaken());
        Log.i(TAG, "Published verified " + (item.mime().startsWith("video/") ? "video" : "photo"));
        advance(account, job, false);
    }

    private void discard(Job job) {
        if (job.pending != null) {
            context.getContentResolver().delete(job.pending, null, null);
            job.pending = null;
        }
    }

    private void advance(int account, Job job, boolean skipped) throws IOException, JSONException {
        Uri previous = job.pending;
        job.pending = null;
        job.next++;
        if (skipped) job.skipped++;
        try {
            save(account, job);
        } catch (IOException | JSONException error) {
            job.next--;
            if (skipped) job.skipped--;
            job.pending = previous;
            throw error;
        }
    }

    void save(int account, Job job) throws IOException, JSONException {
        JSONObject json = new JSONObject()
                .put("name", job.name).put("volume", job.folder.volume()).put("path", job.folder.path())
                .put("image", string(job.folder.image())).put("video", string(job.folder.video()))
                .put("keys", new JSONArray(job.keys)).put("next", job.next).put("skipped", job.skipped)
                .put("pending", string(job.pending));
        if (!journal.edit().putString(key(account), json.toString()).commit()) throw new IOException("Could not save journal");
    }

    private static String key(int account) { return "download_" + account; }
    private static String string(Uri uri) { return uri == null ? "" : uri.toString(); }
    private static Uri uri(JSONObject json, String key) {
        String value = json.optString(key);
        return value.isEmpty() ? null : Uri.parse(value);
    }

    private static final class DownloadFailure extends IOException {
        DownloadFailure(String message) { super(message); }
        DownloadFailure(String message, Throwable cause) { super(message, cause); }
    }
}
