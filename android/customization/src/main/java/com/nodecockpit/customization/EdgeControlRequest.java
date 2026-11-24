package com.nodecockpit.customization;

import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;

import java.util.UUID;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/** One Wirehelm connection for the lifetime of the open control page. */
final class EdgeControlRequest {
    private static final Uri URI = Uri.parse("content://com.example.remote_control.edge.controls");
    private static final ThreadPoolExecutor WORKER = new ThreadPoolExecutor(
        0, 1, 5, TimeUnit.SECONDS, new LinkedBlockingQueue<>());

    private static final ThreadPoolExecutor CLOSER = new ThreadPoolExecutor(
        0, 1, 5, TimeUnit.SECONDS, new LinkedBlockingQueue<>());

    private final String owner = UUID.randomUUID().toString();
    private final Context context;
    private final Handler main;
    private volatile boolean closed;
    private final boolean keyboard;

    EdgeControlRequest(Context context, Handler main) {
        this(context, main, false);
    }

    EdgeControlRequest(Context context, Handler main, boolean keyboard) {
        this.context = context;
        this.main = main;
        this.keyboard = keyboard;
    }

    void call(String method, Bundle payload, Consumer<Bundle> result) {
        if (closed) return;
        WORKER.execute(() -> {
            if (closed) return;
            Bundle reply = invoke(method, payload);
            if (reply == null) {
                reply = new Bundle();
                reply.putString("error", "Control unavailable. Refresh to retry.");
            }
            Bundle response = reply;
            main.post(() -> { if (!closed) result.accept(response); });
        });
    }

    void close() {
        closed = true;
        if (keyboard) CLOSER.execute(() -> invoke("closeKeyboard", null));
        else WORKER.execute(() -> invoke("close", null));
    }

    private Bundle invoke(String method, Bundle payload) {
        try { return context.getContentResolver().call(URI, method, owner, payload); }
        catch (RuntimeException ignored) { return null; }
    }
}
