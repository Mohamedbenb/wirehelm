package com.nodecockpit.customization;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.os.CancellationSignal;
import android.util.LruCache;
import android.util.Size;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.GridView;
import android.widget.ImageView;

import java.io.IOException;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/** A grid of size-limited thumbnails served by Photos' own content provider. */
final class CloudCameraGrid extends BaseAdapter {
    private final Activity activity;
    private final List<CloudCameraMedia.Photo> photos;
    private final ExecutorService thumbnails = Executors.newFixedThreadPool(2);
    private final CancellationSignal closed = new CancellationSignal();
    private final LruCache<Uri, Bitmap> cache = new LruCache<>(10 * 1024 * 1024) {
        @Override protected int sizeOf(Uri uri, Bitmap bitmap) { return bitmap.getAllocationByteCount(); }
    };
    private final int spacing;
    private final int cellSize;

    private CloudCameraGrid(Activity activity, List<CloudCameraMedia.Photo> photos) {
        this.activity = activity;
        this.photos = photos;
        float density = activity.getResources().getDisplayMetrics().density;
        spacing = Math.round(2 * density);
        cellSize = Math.round(96 * density);
    }

    static AlertDialog show(Activity activity, String title, List<CloudCameraMedia.Photo> photos,
                            Consumer<CloudCameraMedia.Photo> openPhoto, Runnable back,
                            Consumer<AlertDialog> onClosed, Runnable downloadGroup) {
        CloudCameraGrid adapter = new CloudCameraGrid(activity, photos);
        GridView grid = new GridView(activity);
        grid.setNumColumns(GridView.AUTO_FIT);
        grid.setColumnWidth(adapter.cellSize);
        grid.setHorizontalSpacing(adapter.spacing);
        grid.setVerticalSpacing(adapter.spacing);
        grid.setAdapter(adapter);
        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setTitle(title + " · " + photos.size())
                .setView(grid)
                .setPositiveButton("Download group", (unused, which) -> downloadGroup.run())
                .setNegativeButton("Back", (unused, which) -> back.run())
                .create();
        dialog.setOnDismissListener(unused -> {
            adapter.close();
            onClosed.accept(dialog);
        });
        grid.setOnItemClickListener((parent, view, position, id) -> {
            dialog.dismiss();
            openPhoto.accept(photos.get(position));
        });
        dialog.show();
        return dialog;
    }

    private void close() {
        closed.cancel();
        thumbnails.shutdownNow();
        cache.evictAll();
    }

    @Override public int getCount() { return photos.size(); }
    @Override public CloudCameraMedia.Photo getItem(int position) { return photos.get(position); }
    @Override public long getItemId(int position) { return position; }

    @Override public View getView(int position, View recycled, ViewGroup parent) {
        ImageView image;
        if (recycled instanceof ImageView existing) {
            image = existing;
        } else {
            image = new ImageView(activity);
            image.setLayoutParams(new AbsListView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, cellSize));
            image.setScaleType(ImageView.ScaleType.CENTER_CROP);
            image.setBackgroundColor(Color.GRAY);
        }
        image.setContentDescription("Item " + (position + 1));
        Uri uri = getItem(position).thumbnail();
        image.setTag(uri);
        Bitmap existing = uri == null ? null : cache.get(uri);
        image.setImageBitmap(existing);
        if (uri != null && existing == null && !closed.isCanceled()) {
            thumbnails.execute(() -> loadThumbnail(image, uri));
        }
        return image;
    }

    private void loadThumbnail(ImageView image, Uri uri) {
        if (closed.isCanceled()) return;
        try {
            Bitmap bitmap = activity.getContentResolver().loadThumbnail(
                    uri, new Size(cellSize, cellSize), closed);
            activity.runOnUiThread(() -> {
                if (closed.isCanceled()) return;
                cache.put(uri, bitmap);
                if (uri.equals(image.getTag())) image.setImageBitmap(bitmap);
            });
        } catch (IOException | RuntimeException unavailable) {
            // The native viewer can still open a photo whose thumbnail is temporarily unavailable.
        }
    }
}
