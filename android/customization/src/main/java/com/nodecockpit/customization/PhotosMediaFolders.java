package com.nodecockpit.customization;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.provider.MediaStore;
import android.provider.MediaStore.MediaColumns;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class PhotosMediaFolders {
    record Folder(String volume, String path, Uri image, Uri video) {
        String label() {
            String trimmed = path.substring(0, path.length() - 1);
            return trimmed.substring(trimmed.lastIndexOf('/') + 1);
        }

        String detail() {
            return volume.equals(MediaStore.VOLUME_EXTERNAL_PRIMARY) ? path : volume + " / " + path;
        }
    }

    private record Location(String volume, String path) {}

    static List<Folder> existing(ContentResolver resolver, CancellationSignal signal) {
        Map<Location, Uri> images = new HashMap<>();
        Map<Location, Uri> videos = new HashMap<>();
        collect(resolver, false, images, signal);
        collect(resolver, true, videos, signal);
        List<Folder> folders = new ArrayList<>();
        images.forEach((location, uri) -> folders.add(
                new Folder(location.volume(), location.path(), uri, videos.remove(location))));
        videos.forEach((location, uri) -> folders.add(new Folder(location.volume(), location.path(), null, uri)));
        folders.sort(Comparator.comparing(Folder::label, String.CASE_INSENSITIVE_ORDER).thenComparing(Folder::detail));
        return folders;
    }

    private static void collect(ContentResolver resolver, boolean video, Map<Location, Uri> folders,
                                CancellationSignal signal) {
        Uri collection = collection(MediaStore.VOLUME_EXTERNAL, video);
        try (Cursor rows = resolver.query(collection,
                new String[]{MediaColumns._ID, MediaColumns.VOLUME_NAME, MediaColumns.RELATIVE_PATH},
                null, null, null, signal)) {
            if (rows == null) return;
            while (rows.moveToNext()) {
                signal.throwIfCanceled();
                String volume = rows.getString(1);
                String path = rows.getString(2);
                if (volume == null || path == null || path.isEmpty() || !path.endsWith("/")) continue;
                var location = new Location(volume, path);
                folders.putIfAbsent(location, ContentUris.withAppendedId(collection(volume, video), rows.getLong(0)));
            }
        }
    }

    static Folder create(String name, boolean camera, boolean containsVideo) {
        String cleaned = name.trim();
        if (cleaned.isEmpty() || cleaned.startsWith(".") || cleaned.length() > 100
                || !cleaned.equals(safeName(cleaned))) throw new IllegalArgumentException("Invalid folder name");
        String parent = camera ? "DCIM/" : containsVideo ? "Movies/" : "Pictures/";
        return new Folder(MediaStore.VOLUME_EXTERNAL_PRIMARY, parent + cleaned + "/", null, null);
    }

    static String safeName(String name) {
        return name.replaceAll("[/\\\\:*?\"<>|\\p{Cc}\\p{Cf}]", "_");
    }

    static Uri reserve(ContentResolver resolver, Folder folder, CloudCameraIndex.Download item) throws IOException {
        boolean video = item.mime().startsWith("video/");
        Uri collection = collection(folder.volume(), video);
        ContentValues values = new ContentValues();
        values.put(MediaColumns.DISPLAY_NAME, safeName(item.name()));
        values.put(MediaColumns.MIME_TYPE, item.mime());
        values.put(MediaColumns.RELATIVE_PATH, folder.path());
        values.put(MediaColumns.DATE_TAKEN, item.dateTaken());
        values.put(MediaColumns.IS_PENDING, 1);
        Bundle options = new Bundle();
        Uri related = video ? folder.video() : folder.image();
        if (related != null) options.putParcelable(MediaStore.QUERY_ARG_RELATED_URI, related);
        Uri result = resolver.insert(collection, values, options);
        if (result == null) throw new IOException("Android rejected the destination");
        return result;
    }

    static void transfer(ContentResolver resolver, Uri original, Uri target, long expectedBytes,
                         CancellationSignal signal) throws IOException {
        try (var source = resolver.openAssetFileDescriptor(original, "r", signal);
             InputStream input = source == null ? null : source.createInputStream();
             OutputStream output = resolver.openOutputStream(target, "wt")) {
            if (input == null || output == null) throw new IOException("Media stream unavailable");
            long count = 0;
            byte[] buffer = new byte[128 * 1024];
            int read;
            while ((read = input.read(buffer)) != -1) {
                signal.throwIfCanceled();
                count += read;
                if (count > expectedBytes) throw new IOException("Original file size differs from Photos");
                output.write(buffer, 0, read);
            }
            if (count != expectedBytes) throw new IOException("Original file size differs from Photos");
        }
    }

    static void publish(ContentResolver resolver, Uri target, long dateTaken) throws IOException {
        ContentValues values = new ContentValues();
        values.put(MediaColumns.DATE_TAKEN, dateTaken);
        values.put(MediaColumns.IS_PENDING, 0);
        if (resolver.update(target, values, null, null) != 1) {
            throw new IOException("Could not publish the finished download");
        }
    }

    /** Returns 1 for a pending row, 0 for a published row, and -1 if it no longer exists. */
    static int pendingState(ContentResolver resolver, Uri target) {
        Bundle options = new Bundle();
        options.putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE);
        try (Cursor row = resolver.query(target, new String[]{MediaColumns.IS_PENDING}, options, null)) {
            return row != null && row.moveToFirst() ? row.getInt(0) : -1;
        }
    }

    private static Uri collection(String volume, boolean video) {
        return video ? MediaStore.Video.Media.getContentUri(volume) : MediaStore.Images.Media.getContentUri(volume);
    }
}
