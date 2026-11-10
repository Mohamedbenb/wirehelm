package com.nodecockpit.customization;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.os.CancellationSignal;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** The Photos index is a local cache. Read only the database for the selected account. */
final class CloudCameraIndex {
    static final int PAGE_SIZE = 800;
    private static final int MAX_KEY_CHARS = 128;
    private static final String FROM_CLOUD = " FROM remote_media r JOIN media m USING(dedup_key)"
            + " WHERE m.has_local=0 AND m.is_deleted=0"
            + " AND m.is_hidden=0 AND m.is_archived=0"
            + " AND r.is_hidden=0 AND r.is_archived=0";
    static final String FROM_CLOUD_IMAGES = FROM_CLOUD + " AND r.type='1'";
    static final String METADATA =
            "CASE WHEN length(r.protobuf)<=CAST(? AS INTEGER) THEN r.protobuf END";
    private static final Comparator<Item> NEWEST_FIRST = Comparator
            .comparingLong(Item::timestamp).reversed().thenComparing(Item::key);

    static List<Item> readSources(File database, CancellationSignal cancellation, PhotosSourceRules.FilenameRules rules) {
        if (!database.isFile()) return List.of();
        Map<String, Candidate> candidates = new HashMap<>();
        // Stream the payloads. Sorting this query in SQLite can materialize the whole blob set.
        try (SQLiteDatabase db = open(database);
             Cursor rows = db.rawQuery("SELECT r.dedup_key, m.capture_timestamp, r.type, r.mime_type,"
                     + " r.owner_package_name, r.filename, " + METADATA + ", r.size_bytes" + FROM_CLOUD,
                     new String[]{maxPayload()}, cancellation)) {
            while (rows.moveToNext()) {
                cancellation.throwIfCanceled();
                String key = rows.getString(0);
                if (key == null || key.isBlank() || key.length() > MAX_KEY_CHARS) continue;
                String mime = rows.getString(3);
                boolean video = mime != null && mime.startsWith("video/") || rows.getInt(2) == 2;
                boolean image = mime != null && mime.startsWith("image/") || rows.getInt(2) == 1;
                if (video == image) continue;
                var evidence = PhotosSourceRules.identify(video, rows.getString(4), rows.getString(5),
                        CloudCameraOrigin.camera(rows.getBlob(6)), rules);
                Candidate candidate = candidates.get(key);
                if (candidate == null) {
                    candidates.put(key, new Candidate(rows.getLong(1), rows.getLong(7), video, evidence));
                } else {
                    candidate.add(video, rows.getLong(7), evidence);
                }
            }
        }
        List<Item> items = new ArrayList<>(candidates.size());
        for (Map.Entry<String, Candidate> entry : candidates.entrySet()) {
            Candidate candidate = entry.getValue();
            if (candidate.mediaConflict) continue;
            PhotosSourceRules.Source source = candidate.sourceConflict
                    ? new PhotosSourceRules.Source(candidate.video ? PhotosSourceRules.VIDEOS : PhotosSourceRules.UNSORTED, "")
                    : candidate.evidence.source();
            items.add(new Item(entry.getKey(), candidate.timestamp, candidate.size, candidate.video, source));
        }
        items.sort(NEWEST_FIRST);
        return items;
    }

    record Item(String key, long timestamp, long size, boolean video, PhotosSourceRules.Source source) {}
    record Download(String name, String mime, long size, long dateTaken, boolean local) {}

    static Download download(File database, String key, CancellationSignal request) {
        if (!database.isFile()) return null;
        try (SQLiteDatabase db = open(database);
             Cursor row = db.rawQuery("SELECT r.filename, r.mime_type, r.size_bytes, m.capture_timestamp,"
                     + " m.has_local, r.type FROM remote_media r JOIN media m USING(dedup_key)"
                     + " WHERE r.dedup_key=? AND m.is_deleted=0 AND m.is_hidden=0 AND m.is_archived=0"
                     + " AND r.is_hidden=0 AND r.is_archived=0"
                     + " ORDER BY (r.media_key=m.canonical_media_key) DESC, r.size_bytes DESC LIMIT 1",
                     new String[]{key}, request)) {
            if (!row.moveToFirst()) return null;
            String name = row.getString(0);
            return new Download(name, downloadMime(name, row.getString(1), row.getInt(5)), row.getLong(2),
                    row.getLong(3), row.getInt(4) != 0);
        }
    }

    private static String downloadMime(String name, String stored, int type) {
        String family = type == 2 ? "video/" : "image/";
        if (stored != null && stored.startsWith(family)) return stored;
        if (name == null) return null;
        int separator = name.lastIndexOf('.');
        if (separator < 0) return null;
        String extension = name.substring(separator + 1).toLowerCase(Locale.ROOT);
        String resolved = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
        return resolved != null && resolved.startsWith(family) ? resolved : null;
    }

    private static final class Candidate {
        final long timestamp;
        final boolean video;
        long size;
        PhotosSourceRules.Evidence evidence;
        boolean sourceConflict;
        boolean mediaConflict;

        Candidate(long timestamp, long size, boolean video, PhotosSourceRules.Evidence evidence) {
            this.timestamp = timestamp;
            this.size = size;
            this.video = video;
            this.evidence = evidence;
        }

        void add(boolean video, long size, PhotosSourceRules.Evidence other) {
            mediaConflict |= this.video != video;
            this.size = Math.max(this.size, size);
            if (other.rank() > evidence.rank()) {
                evidence = other;
                sourceConflict = false;
            } else if (other.rank() == evidence.rank() && !other.source().equals(evidence.source())) {
                sourceConflict = true;
            }
        }
    }

    static SQLiteDatabase open(File database) {
        return SQLiteDatabase.openDatabase(database.getPath(), null,
                SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
    }

    static String maxPayload() {
        return Integer.toString(CloudCameraOrigin.MAX_PAYLOAD_BYTES);
    }
}
