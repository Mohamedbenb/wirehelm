package com.nodecockpit.customization;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.CancellationSignal;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.util.Log;

import org.json.JSONException;

import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

/** Runs the same Photos-owned queue as a namespaced, user-initiated Android transfer. */
final class PhotosDownloadJob {
    static final String SERVICE = "com.google.android.apps.photos.backup.core.UserInitiatedBackupJobService";
    private static final String NAMESPACE = "com.nodecockpit.photos.sources";
    private static final String CHANNEL = "wirehelm_photos_source_downloads";
    private static final String PAUSE = NAMESPACE + ".PAUSE";
    private static final String TAG = "WirehelmCloudCamera";
    private static final int JOB_ID = 1;
    private static final int NOTIFICATION_ID = 0x57685044;

    private final Context context;
    private final PhotosSourceDownloads downloads;
    private final JobScheduler scheduler;
    private final NotificationManager notifications;
    private final BiConsumer<String, PhotosSourceDownloads.Progress> status;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private Session active;
    private int observerAccount = -1;
    private Consumer<PhotosSourceDownloads.Progress> observer;

    private static final class Session {
        final JobService service;
        final JobParameters params;
        final int account;
        final String token;
        final CancellationSignal signal = new CancellationSignal();
        PhotosSourceDownloads.Progress progress;
        boolean paused;

        Session(JobService service, JobParameters params) {
            this.service = service;
            this.params = params;
            account = params.getExtras().getInt("account", -1);
            token = params.getExtras().getString("token", "");
        }
    }

    PhotosDownloadJob(Context context, PhotosSourceDownloads downloads,
                      BiConsumer<String, PhotosSourceDownloads.Progress> status) {
        this.context = context;
        this.downloads = downloads;
        this.status = status;
        scheduler = Build.VERSION.SDK_INT >= 34
                ? context.getSystemService(JobScheduler.class).forNamespace(NAMESPACE) : null;
        notifications = context.getSystemService(NotificationManager.class);
        if (scheduler != null) context.registerReceiver(new BroadcastReceiver() {
            @Override public void onReceive(Context ignored, Intent intent) {
                Session current = active;
                if (current != null && current.token.equals(intent.getStringExtra("token"))) {
                    pause(current.account);
                }
            }
        }, new IntentFilter(PAUSE), Context.RECEIVER_NOT_EXPORTED);
    }

    static boolean owns(JobParameters params) {
        return params.getJobId() == JOB_ID && NAMESPACE.equals(params.getJobNamespace())
                && !params.getExtras().getString("token", "").isEmpty();
    }

    boolean isScheduled(int account) {
        if (active != null && active.account == account) return true;
        if (scheduler == null) return false;
        JobInfo pending = scheduler.getPendingJob(JOB_ID);
        return pending != null && pending.getExtras().getInt("account", -1) == account;
    }

    boolean schedule(int account, PhotosSourceDownloads.Job requested, boolean skip)
            throws IOException, JSONException {
        if (scheduler == null) return false;
        if (isScheduled(account)) return true;
        if (active != null || scheduler.getPendingJob(JOB_ID) != null) return false;
        PhotosSourceDownloads.Job saved = downloads.saved(account);
        if (saved == null) {
            saved = requested;
            downloads.save(account, saved);
        }
        PersistableBundle extras = new PersistableBundle();
        extras.putInt("account", account);
        extras.putInt("skipAt", skip ? saved.next : -1);
        extras.putString("token", UUID.randomUUID().toString());
        JobInfo job = new JobInfo.Builder(JOB_ID, new ComponentName(context.getPackageName(), SERVICE))
                .setExtras(extras)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setUserInitiated(true)
                .build();
        if (scheduler.schedule(job) != JobScheduler.RESULT_SUCCESS) return false;
        status.accept("waiting", saved.progress(false, null));
        Log.i(TAG, "Sources background transfer scheduled");
        return true;
    }

    boolean start(JobService service, JobParameters params) {
        Session session = new Session(service, params);
        if (session.account < 0) return false;
        try {
            ensureChannel();
            service.setNotification(params, NOTIFICATION_ID, notification(session, "Preparing download"),
                    JobService.JOB_END_NOTIFICATION_POLICY_DETACH);
            active = session;
            executor.execute(() -> transfer(session));
            Log.i(TAG, "Sources background transfer started");
            return true;
        } catch (RuntimeException error) {
            if (active == session) active = null;
            notifications.cancel(NOTIFICATION_ID);
            Log.w(TAG, "Sources background transfer could not start", error);
            return false;
        }
    }

    private void transfer(Session session) {
        try {
            PhotosSourceDownloads.Job saved = downloads.saved(session.account);
            if (saved == null) {
                deliver(session, new PhotosSourceDownloads.Progress(0, 0, 0, true, null));
                return;
            }
            boolean skip = saved.next == session.params.getExtras().getInt("skipAt", -1);
            downloads.run(session.account, saved, session.signal, skip, progress -> deliver(session, progress));
        } catch (JSONException | RuntimeException error) {
            Log.w(TAG, "Sources background journal could not be read");
            deliver(session, new PhotosSourceDownloads.Progress(0, 0, 1, true,
                    "The saved download could not be read."));
        }
    }

    private void deliver(Session session, PhotosSourceDownloads.Progress progress) {
        main.post(() -> {
            if (active != session) return;
            session.progress = progress;
            if (progress.stopped()) {
                active = null;
                session.service.jobFinished(session.params, false);
                notifyStatus(session, progress);
                Log.i(TAG, progress.finished() ? "Sources background transfer complete" : "Sources background transfer paused");
            } else {
                notifyStatus(session, progress);
            }
            status.accept(progress.stopped() ? progress.finished() ? "complete" : "paused" : "running", progress);
            if (observerAccount == session.account && observer != null) observer.accept(progress);
        });
    }

    boolean stop(JobParameters params) {
        Session session = active;
        if (session == null || !session.token.equals(params.getExtras().getString("token", ""))) return false;
        active = null;
        session.signal.cancel();
        int reason = params.getStopReason();
        boolean retry = !session.paused && reason != JobParameters.STOP_REASON_USER
                && reason != JobParameters.STOP_REASON_CANCELLED_BY_APP;
        if (!retry) {
            PhotosSourceDownloads.Progress progress = session.progress;
            if (progress != null) {
                var stopped = new PhotosSourceDownloads.Progress(progress.done(), progress.skipped(), progress.total(), true, null);
                notifyStatus(session, stopped);
                status.accept("paused", stopped);
                if (observerAccount == session.account && observer != null) observer.accept(stopped);
            } else {
                notifications.cancel(NOTIFICATION_ID);
            }
        } else {
            // The system owns retry timing. Remove the stale active notification.
            notifications.cancel(NOTIFICATION_ID);
            if (session.progress != null) status.accept("waiting", session.progress);
        }
        return retry;
    }

    void pause(int account) {
        Session current = active;
        if (current != null && current.account == account) {
            current.paused = true;
            current.signal.cancel();
        } else if (isScheduled(account)) {
            scheduler.cancel(JOB_ID);
            try {
                var saved = downloads.saved(account);
                if (saved != null) {
                    var progress = saved.progress(true, null);
                    status.accept("paused", progress);
                    if (observerAccount == account && observer != null) observer.accept(progress);
                }
            } catch (JSONException ignored) {
                Log.w(TAG, "Sources background journal could not be read");
            }
        }
    }

    void observe(int account, Consumer<PhotosSourceDownloads.Progress> listener) {
        observerAccount = account;
        observer = listener;
        if (active != null && active.account == account && active.progress != null) listener.accept(active.progress);
    }

    void removeObserver(Consumer<PhotosSourceDownloads.Progress> listener) {
        if (observer == listener) {
            observerAccount = -1;
            observer = null;
        }
    }

    private void ensureChannel() {
        NotificationChannel channel = new NotificationChannel(CHANNEL, "Sources downloads",
                NotificationManager.IMPORTANCE_LOW);
        channel.setShowBadge(false);
        notifications.createNotificationChannel(channel);
    }

    private void notifyStatus(Session session, PhotosSourceDownloads.Progress progress) {
        try {
            String counts = progress.done() + " saved · " + progress.skipped() + " skipped · " + progress.total() + " total";
            if (progress.stopped()) {
                String title = progress.finished() ? "Sources download complete" : "Sources download paused";
                notifications.notify(NOTIFICATION_ID, builder(title, counts).setAutoCancel(true).build());
            } else {
                session.service.setNotification(session.params, NOTIFICATION_ID, builder("Downloading from Sources", counts)
                        .setOngoing(true).setProgress(progress.total(), progress.done() + progress.skipped(), false)
                        .addAction(pauseAction(session)).build(), JobService.JOB_END_NOTIFICATION_POLICY_DETACH);
            }
        } catch (RuntimeException error) {
            Log.w(TAG, "Sources progress notification unavailable");
        }
    }

    private Notification notification(Session session, String message) {
        return builder("Downloading from Sources", message).setOngoing(true).setProgress(0, 0, true)
                .addAction(pauseAction(session)).build();
    }

    private Notification.Builder builder(String title, String message) {
        Intent home = new Intent().setClassName(context.getPackageName(),
                context.getPackageName() + ".home.HomeActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent open = PendingIntent.getActivity(context, 0, home, PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(context, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title).setContentText(message).setContentIntent(open)
                .setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE);
    }

    private Notification.Action pauseAction(Session session) {
        Intent pause = new Intent(PAUSE).setPackage(context.getPackageName()).putExtra("token", session.token);
        PendingIntent action = PendingIntent.getBroadcast(context, session.token.hashCode(), pause, PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Action.Builder(null, "Pause", action).build();
    }
}
