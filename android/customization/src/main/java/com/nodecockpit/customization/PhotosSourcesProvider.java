package com.nodecockpit.customization;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;

/** Photos may read settings and report aggregate status. Configuration writes stay in Wirehelm. */
public final class PhotosSourcesProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }

    @Override public Bundle call(String method, String arg, Bundle extras) {
        var context = getContext();
        if (context == null || !PhotosSourcesControl.isPhotos(context, Binder.getCallingUid(), getCallingPackage())) {
            throw new SecurityException("Photos only");
        }
        long identity = Binder.clearCallingIdentity();
        try (ProcessWork.Token request=ProcessWork.begin("Photos support request")) {
            if ("settings".equals(method)) return PhotosSourcesControl.settings(context);
            if ("status".equals(method) && extras != null) {
                PhotosSourcesControl.report(context, extras);
                return Bundle.EMPTY;
            }
            throw new UnsupportedOperationException();
        } finally {
            Binder.restoreCallingIdentity(identity);
        }
    }

    @Override public Cursor query(Uri uri, String[] fields, String where, String[] args, String order) {
        throw new UnsupportedOperationException();
    }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String where, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String where, String[] args) {
        throw new UnsupportedOperationException();
    }
}
