package com.nodecockpit.customization;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.os.Build;

import java.io.File;
import java.util.EnumMap;

/** Read-only prototype. Uses a selected sample to identify one index and reports counts only. */
public final class PhotosCameraIndexProbe {
    public static void main(String[] args) {
        if (args.length != 3 || !Integer.toString(CloudCameraOrigin.PHOTOS_VERSION_CODE).equals(args[0])) {
            throw new IllegalArgumentException("Expected verified Photos version, sample filename, and source package");
        }
        File directory = new File("/data/user/0/com.google.android.apps.photos/databases");
        File[] candidates = directory.listFiles(file -> file.isFile() && file.length() >= 4096
                && !file.getName().matches(".*-(wal|shm|journal)$"));
        if (candidates == null) throw new IllegalStateException("Photos index is inaccessible");

        File match = null;
        CloudCameraOrigin.Source sample = null;
        for (File candidate : candidates) {
            CloudCameraOrigin.Source found = sampleIn(candidate, args[1], args[2]);
            if (found == null) continue;
            if (match != null) throw new IllegalStateException("The sample appears in multiple indexes");
            match = candidate;
            sample = found;
        }
        if (match == null) throw new IllegalStateException("Cloud-only sample not found in a supported index");
        System.out.println("Cloud-only sample classification: " + sample);
        summarize(match);
    }

    private static CloudCameraOrigin.Source sampleIn(File file, String filename, String owner) {
        try (SQLiteDatabase db = CloudCameraIndex.open(file);
             Cursor row = db.rawQuery("SELECT " + CloudCameraIndex.METADATA + CloudCameraIndex.FROM_CLOUD_IMAGES
                     + " AND r.filename=? AND r.owner_package_name=? LIMIT 2",
                     new String[]{CloudCameraIndex.maxPayload(), filename, owner})) {
            if (!row.moveToFirst()) return null;
            CloudCameraOrigin.Source source = CloudCameraOrigin.classify(row.getBlob(0), Build.MODEL);
            if (row.moveToNext()) throw new IllegalStateException("Multiple records match the selected sample");
            return source;
        } catch (SQLiteException unavailableSchema) {
            return null;
        }
    }

    private static void summarize(File file) {
        EnumMap<CloudCameraOrigin.Source, Integer> counts = new EnumMap<>(CloudCameraOrigin.Source.class);
        try (SQLiteDatabase db = CloudCameraIndex.open(file);
             Cursor rows = db.rawQuery("SELECT " + CloudCameraIndex.METADATA + CloudCameraIndex.FROM_CLOUD_IMAGES,
                     new String[]{CloudCameraIndex.maxPayload()})) {
            while (rows.moveToNext()) {
                CloudCameraOrigin.Source source = CloudCameraOrigin.classify(rows.getBlob(0), Build.MODEL);
                counts.merge(source, 1, Integer::sum);
            }
        }
        for (CloudCameraOrigin.Source source : CloudCameraOrigin.Source.values()) {
            System.out.println(source + " cloud image records: " + counts.getOrDefault(source, 0));
        }
    }

}
