package com.nodecockpit.customization;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Application;
import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Context;
import android.os.Bundle;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.SystemClock;
import android.text.format.Formatter;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;

import org.json.JSONException;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.WeakHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;

/** Version-specific adapter for the Photos Collections tab. */
public final class PhotosCloudCameraModule extends XposedModule {
    private static final String PHOTOS = "com.google.android.apps.photos";
    private static final String HOME = PHOTOS + ".home.HomeActivity";
    private static final String TAG = "WirehelmCloudCamera";
    private static final String TITLE = "Sources";
    private final ExecutorService indexReader = Executors.newSingleThreadExecutor();
    private final ExecutorService controlWorker = Executors.newSingleThreadExecutor();
    private boolean checked;

    @Override public void onModuleLoaded(ModuleLoadedParam param) {
        if (param.isSystemServer() || !PHOTOS.equals(param.getProcessName())) return;
        try {
            Method attach = android.app.Application.class.getDeclaredMethod("attach", Context.class);
            hook(attach).intercept(new XposedInterface.Hooker() {
                @Override public Object intercept(XposedInterface.Chain chain) throws Throwable {
                    Object result = chain.proceed();
                    Context context = (Context) chain.getArg(0);
                    if (PHOTOS.equals(context.getPackageName())) {
                        install((Application) chain.getThisObject(), context);
                    }
                    return result;
                }
            });
        } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
            report("Application hook", error);
        }
    }

    private synchronized void install(Application application, Context context) {
        if (checked) return;
        checked = true;
        try {
            long version = context.getPackageManager().getPackageInfo(PHOTOS, 0).getLongVersionCode();
            if (version != CloudCameraOrigin.PHOTOS_VERSION_CODE) {
                Log.i(TAG, "Unsupported Photos version " + version);
                return;
            }
            ClassLoader loader = context.getClassLoader();
            Class<?> fragment = Class.forName("xnx", false, loader);
            PhotosBindings bindings = new PhotosBindings(loader, fragment, application);
            if (Build.VERSION.SDK_INT >= 34) bindDownloadJob(loader, bindings);
            application.registerActivityLifecycleCallbacks(new CollectionsObserver(bindings, fragment));
            Log.i(TAG, "Collections hook ready for Photos " + version);
        } catch (ReflectiveOperationException | android.content.pm.PackageManager.NameNotFoundException
                 | RuntimeException | LinkageError error) {
            report("Photos binding", error);
        }
    }

    private void bindDownloadJob(ClassLoader loader, PhotosBindings bindings) {
        try {
            Class<?> service = loader.loadClass(PhotosDownloadJob.SERVICE);
            Method start = service.getDeclaredMethod("onStartJob", JobParameters.class);
            Method stop = service.getDeclaredMethod("onStopJob", JobParameters.class);
            hook(start).intercept(new XposedInterface.Hooker() {
                @Override public Object intercept(XposedInterface.Chain chain) throws Throwable {
                    JobParameters params = (JobParameters) chain.getArg(0);
                    return PhotosDownloadJob.owns(params)
                            ? bindings.background.start((JobService) chain.getThisObject(), params) : chain.proceed();
                }
            });
            hook(stop).intercept(new XposedInterface.Hooker() {
                @Override public Object intercept(XposedInterface.Chain chain) throws Throwable {
                    JobParameters params = (JobParameters) chain.getArg(0);
                    return PhotosDownloadJob.owns(params) ? bindings.background.stop(params) : chain.proceed();
                }
            });
            bindings.backgroundReady = true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
            report("Background download service", error);
        }
    }

    private final class CollectionsObserver implements Application.ActivityLifecycleCallbacks {
        private final PhotosBindings bindings;
        private final Class<?> fragmentType;
        private final Map<Activity, ViewTreeObserver.OnGlobalLayoutListener> observers = new IdentityHashMap<>();
        private final Map<View, Boolean> bound = new WeakHashMap<>();

        CollectionsObserver(PhotosBindings bindings, Class<?> fragmentType) {
            this.bindings = bindings;
            this.fragmentType = fragmentType;
        }

        @Override public void onActivityResumed(Activity activity) {
            if (!HOME.equals(activity.getClass().getName()) || observers.containsKey(activity)) return;
            int gridId = viewId(activity, "photos_collectionstab_grid_view");
            int toolbarId = viewId(activity, "toolbar");
            int fragmentTag = viewId(activity, "fragment_container_view_tag");
            if (gridId == 0 || toolbarId == 0 || fragmentTag == 0) return;
            ViewTreeObserver.OnGlobalLayoutListener observer = () -> bind(activity, gridId, toolbarId, fragmentTag);
            observers.put(activity, observer);
            activity.getWindow().getDecorView().getViewTreeObserver().addOnGlobalLayoutListener(observer);
            observer.onGlobalLayout();
            controlWorker.execute(() -> {
                bindings.refreshSettings();
                bindings.reportStatus(null, null);
                activity.runOnUiThread(() -> {
                    if (observers.containsKey(activity)) activity.getWindow().getDecorView().requestLayout();
                });
            });
        }

        private void bind(Activity activity, int gridId, int toolbarId, int fragmentTag) {
            try {
                View grid = activity.findViewById(gridId);
                if (grid == null || !grid.isShown() || bound.containsKey(grid)
                        || !(grid.getParent() instanceof ViewGroup root)
                        || !(grid.getLayoutParams() instanceof ViewGroup.MarginLayoutParams)) return;
                Object fragment = root.getTag(fragmentTag);
                if (!fragmentType.isInstance(fragment)) {
                    if (fragment != null) {
                        bound.put(grid, false);
                        Log.w(TAG, "Unsupported Collections owner " + fragment.getClass().getName());
                    }
                    return;
                }
                bound.put(grid, true);
                new Entry(bindings, fragment, activity, root, grid, toolbarId,
                        () -> observers.containsKey(activity)).attach();
                Log.i(TAG, "Sources entry attached to Collections view");
            } catch (RuntimeException | LinkageError error) {
                onActivityPaused(activity);
                report("Collections entry", error);
            }
        }

        @Override public void onActivityPaused(Activity activity) {
            ViewTreeObserver.OnGlobalLayoutListener observer = observers.remove(activity);
            if (observer != null) {
                activity.getWindow().getDecorView().getViewTreeObserver().removeOnGlobalLayoutListener(observer);
            }
        }

        @Override public void onActivityCreated(Activity activity, Bundle state) {}
        @Override public void onActivityStarted(Activity activity) {}
        @Override public void onActivityStopped(Activity activity) {}
        @Override public void onActivitySaveInstanceState(Activity activity, Bundle state) {}
        @Override public void onActivityDestroyed(Activity activity) { onActivityPaused(activity); }
    }

    private final class Entry implements View.OnAttachStateChangeListener {
        private final PhotosBindings bindings;
        private final Object fragment;
        private final Activity activity;
        private final ViewGroup root;
        private final View grid;
        private final Button button;
        private final int toolbarId;
        private final BooleanSupplier resumed;
        private final int gridTopMargin;
        private final int[] rootLocation = new int[2];
        private final int[] toolbarLocation = new int[2];
        private final ViewTreeObserver.OnGlobalLayoutListener layout = this::place;
        private CancellationSignal pending;
        private CancellationSignal downloadSignal;
        private AlertDialog shown;

        Entry(PhotosBindings bindings, Object fragment, Activity activity,
              ViewGroup root, View grid, int toolbarId, BooleanSupplier resumed) {
            this.bindings = bindings;
            this.fragment = fragment;
            this.activity = activity;
            this.root = root;
            this.grid = grid;
            this.toolbarId = toolbarId;
            this.resumed = resumed;
            gridTopMargin = ((ViewGroup.MarginLayoutParams) grid.getLayoutParams()).topMargin;
            button = new Button(root.getContext());
            button.setText(TITLE);
            button.setAllCaps(false);
            button.setVisibility(View.GONE);
            button.setOnClickListener(unused -> load());
        }

        void attach() {
            ViewGroup.MarginLayoutParams params = new ViewGroup.MarginLayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            params.setMarginStart(dp(16));
            root.addView(button, params);
            root.addOnAttachStateChangeListener(this);
            if (root.isAttachedToWindow()) onViewAttachedToWindow(root);
        }

        @Override public void onViewAttachedToWindow(View view) {
            root.getViewTreeObserver().addOnGlobalLayoutListener(layout);
        }

        @Override public void onViewDetachedFromWindow(View view) {
            root.getViewTreeObserver().removeOnGlobalLayoutListener(layout);
            if (pending != null) pending.cancel();
            pending = null;
            if (downloadSignal != null) downloadSignal.cancel();
            if (shown != null) shown.dismiss();
            button.setEnabled(true);
        }

        private boolean isCurrent() {
            return resumed.getAsBoolean() && !activity.isFinishing() && !activity.isDestroyed() && root.isShown()
                    && root.isAttachedToWindow() && root.getWindowVisibility() == View.VISIBLE;
        }

        private void place() {
            try {
                View toolbar = activity.findViewById(toolbarId);
                if (!isCurrent() || !bindings.enabled() || toolbar == null || !toolbar.isLaidOut()) {
                    button.setVisibility(View.GONE);
                    updateTop(grid, gridTopMargin);
                    return;
                }
                root.getLocationInWindow(rootLocation);
                toolbar.getLocationInWindow(toolbarLocation);
                int top = bindings.topInset.getInt(fragment);
                int toolbarBottom = toolbarLocation[1] + toolbar.getHeight() - rootLocation[1];
                int buttonTop = Math.max(top, toolbarBottom);
                int rowHeight = Math.max(dp(52), button.getMeasuredHeight());
                updateTop(button, buttonTop);
                updateTop(grid, gridTopMargin + rowHeight + Math.max(0, buttonTop - top));
                button.setVisibility(View.VISIBLE);
            } catch (IllegalAccessException | RuntimeException | LinkageError error) {
                root.getViewTreeObserver().removeOnGlobalLayoutListener(layout);
                updateTop(grid, gridTopMargin);
                root.removeView(button);
                root.removeOnAttachStateChangeListener(this);
                report("Collections layout", error);
            }
        }

        private int dp(int value) {
            return Math.round(value * root.getResources().getDisplayMetrics().density);
        }

        private int account() throws ReflectiveOperationException {
            int active = (Integer) bindings.accountId.invoke(bindings.accountProvider.invoke(fragment));
            Object model = bindings.viewModel.get(fragment);
            return model != null && active >= 0 && active == bindings.modelAccount.getInt(model) ? active : -1;
        }

        private void load() {
            if (pending != null || !isCurrent() || !bindings.enabled()) return;
            try {
                int account = account();
                if (account < 0) {
                    message("Select a Google Photos account to open Sources.");
                    return;
                }
                File database = activity.getDatabasePath("gphotos" + account + ".db");
                CancellationSignal request = new CancellationSignal();
                pending = request;
                button.setEnabled(false);
                indexReader.execute(() -> {
                    try {
                        var config = bindings.settings;
                        if (config == null || !config.enabled()) {
                            activity.runOnUiThread(() -> results(request, account, null));
                            return;
                        }
                        var rules = new PhotosSourceRules.FilenameRules(
                                config.messengerNames(), config.facebookNames(), config.whatsappNames());
                        List<CloudCameraIndex.Item> items = CloudCameraIndex.readSources(database, request, rules);
                        activity.runOnUiThread(() -> results(request, account, items));
                    } catch (RuntimeException | LinkageError error) {
                        if (!request.isCanceled()) report("Sources index", error);
                        activity.runOnUiThread(() -> results(request, account, null));
                    }
                });
            } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
                unavailable(error);
            }
        }

        private void results(CancellationSignal request, int account, List<CloudCameraIndex.Item> items) {
            if (pending != request) return;
            pending = null;
            button.setEnabled(true);
            try {
                if (request.isCanceled() || !isCurrent() || !bindings.enabled() || account != account()) return;
                if (items == null) {
                    message("Sources could not read this account’s Photos index.");
                } else if (items.isEmpty()) {
                    message("No cloud-only photos or videos are cached for this account.");
                } else {
                    showSources(account, items);
                }
            } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
                unavailable(error);
            }
        }

        private void showSources(int account, List<CloudCameraIndex.Item> items) {
            if (!currentAccount(account)) return;
            var config = bindings.settings;
            if (config == null || !config.enabled()) return;
            boolean development = config.development().equals("on")
                    || config.development().equals("existing") && activity.getSharedPreferences(
                            "wirehelm_photos_sources", Context.MODE_PRIVATE).getBoolean("development_" + account, false);
            Map<String, List<CloudCameraIndex.Item>> groups = new TreeMap<>();
            for (var item : items) {
                String group = item.source().group();
                if (!development && group.equals(PhotosSourceRules.DEVELOPMENT)) group = PhotosSourceRules.UNSORTED;
                groups.computeIfAbsent(group, unused -> new ArrayList<>()).add(item);
            }
            List<String> names = new ArrayList<>(groups.keySet());
            names.sort(Comparator.comparing((String name) -> name.equals(PhotosSourceRules.UNSORTED))
                    .thenComparing(Comparator.comparingInt((String name) -> groups.get(name).size()).reversed())
                    .thenComparing(Comparator.naturalOrder()));
            int videoCount = (int) items.stream().filter(CloudCameraIndex.Item::video).count();
            AlertDialog.Builder sourceList = new AlertDialog.Builder(activity)
                    .setTitle(TITLE + " · " + (items.size() - videoCount) + " photos · " + videoCount + " videos")
                    .setItems(labels(names, groups), (dialog, which) -> {
                        String name = names.get(which);
                        Runnable back = () -> showSources(account, items);
                        if (name.equals(PhotosSourceRules.CAMERA)) showCamera(account, groups.get(name), back);
                        else selectPage(account, name, groups.get(name), back);
                    })
                    .setNegativeButton("Close", null);
            var job = savedDownload(account);
            if (job != null && !bindings.background.isScheduled(account)) {
                bindings.queueStatus("paused", job.progress(true, null));
            }
            if (job != null) sourceList.setPositiveButton(
                    bindings.background.isScheduled(account) ? "Download progress" : "Resume download",
                    (dialog, which) -> runDownload(account, job, false, () -> showSources(account, items)));
            show(sourceList);
        }

        private void showCamera(int account, List<CloudCameraIndex.Item> items, Runnable back) {
            if (!currentAccount(account)) return;
            Map<String, List<CloudCameraIndex.Item>> models = new TreeMap<>();
            for (var item : items) models.computeIfAbsent(item.source().model(), unused -> new ArrayList<>()).add(item);
            List<String> names = new ArrayList<>(models.keySet());
            Runnable returnToCamera = () -> showCamera(account, items, back);
            show(new AlertDialog.Builder(activity).setTitle(PhotosSourceRules.CAMERA + " · " + items.size())
                    .setItems(labels(names, models), (dialog, which) -> {
                        String name = names.get(which);
                        selectPage(account, name, models.get(name), returnToCamera);
                    })
                    .setPositiveButton("Download all Camera",
                            (dialog, which) -> chooseFolder(account, PhotosSourceRules.CAMERA, items, returnToCamera))
                    .setNegativeButton("Sources", (dialog, which) -> back.run()));
        }

        private void selectPage(int account, String name, List<CloudCameraIndex.Item> items, Runnable back) {
            if (!currentAccount(account)) return;
            int size = CloudCameraIndex.PAGE_SIZE;
            if (items.size() <= size) {
                open(account, name, items, items, back);
                return;
            }
            List<String> pages = new ArrayList<>();
            for (int offset = 0; offset < items.size(); offset += size) {
                pages.add((offset + 1) + "–" + Math.min(offset + size, items.size()));
            }
            show(new AlertDialog.Builder(activity).setTitle(name + " · " + items.size())
                    .setItems(pages.toArray(String[]::new), (dialog, which) -> {
                        int offset = which * size;
                        open(account, name + " · " + pages.get(which),
                                items.subList(offset, Math.min(offset + size, items.size())), items,
                                () -> selectPage(account, name, items, back));
                    })
                    .setPositiveButton("Download group", (dialog, which) -> chooseFolder(account, name, items, back))
                    .setNegativeButton("Back", (dialog, which) -> back.run()));
        }

        private String[] labels(List<String> names, Map<String, List<CloudCameraIndex.Item>> groups) {
            return names.stream().map(name -> name + " · " + groups.get(name).size()).toArray(String[]::new);
        }

        private void show(AlertDialog.Builder builder) {
            track(builder.show());
        }

        private void track(AlertDialog dialog) {
            shown = dialog;
            dialog.setOnDismissListener(unused -> clearDialog(dialog));
        }

        private void clearDialog(AlertDialog dialog) {
            if (shown == dialog) shown = null;
        }

        private boolean currentAccount(int account) {
            try {
                return isCurrent() && account == account();
            } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
                unavailable(error);
                return false;
            }
        }

        private void open(int account, String name, List<CloudCameraIndex.Item> items,
                          List<CloudCameraIndex.Item> group, Runnable back) {
            if (pending != null || !currentAccount(account)) return;
            try {
                CancellationSignal request = new CancellationSignal();
                pending = request;
                button.setEnabled(false);
                indexReader.execute(() -> {
                    try {
                        List<String> keys = new ArrayList<>(items.size());
                        for (var item : items) keys.add(item.key());
                        CloudCameraMedia.Collection photos =
                                bindings.media.load(activity, account, keys, request);
                        activity.runOnUiThread(() -> showGrid(request, account, name, photos, group, back));
                    } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
                        if (!request.isCanceled()) report("Native media lookup", error);
                        activity.runOnUiThread(() -> showGrid(request, account, name, null, group, back));
                    }
                });
            } catch (RuntimeException | LinkageError error) {
                unavailable(error);
            }
        }

        private void showGrid(CancellationSignal request, int account, String name,
                              CloudCameraMedia.Collection photos, List<CloudCameraIndex.Item> group, Runnable back) {
            if (pending != request) return;
            pending = null;
            button.setEnabled(true);
            try {
                // A source dialog can still be releasing focus when a small group finishes loading.
                if (request.isCanceled() || !isCurrent() || account != account()) return;
                if (photos == null || photos.photos().isEmpty()) {
                    message("Photos could not load these results.");
                    back.run();
                    return;
                }
                shown = CloudCameraGrid.show(activity, name, photos.photos(),
                        photo -> openPhoto(account, photos, photo), back, this::clearDialog,
                        () -> chooseFolder(account, group.get(0).source().group(), group, back));
                Log.i(TAG, "Opened Sources grid with " + photos.photos().size() + " items");
            } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
                unavailable(error);
            }
        }

        private void openPhoto(int account, CloudCameraMedia.Collection photos, CloudCameraMedia.Photo photo) {
            try {
                if (!isCurrent() || account != account()) return;
                bindings.media.open(activity, photos, photo);
                Log.i(TAG, "Opened native Photos viewer");
            } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
                unavailable(error);
            }
        }

        private PhotosSourceDownloads.Job savedDownload(int account) {
            try {
                return bindings.downloads.saved(account);
            } catch (JSONException | RuntimeException error) {
                unavailable(error);
                return null;
            }
        }

        private void chooseFolder(int account, String name, List<CloudCameraIndex.Item> items, Runnable back) {
            if (!currentAccount(account) || pending != null || items.isEmpty()) return;
            var saved = savedDownload(account);
            if (saved != null) {
                show(new AlertDialog.Builder(activity).setTitle("Download already queued")
                        .setMessage(saved.name + "\n" + saved.folder.detail())
                        .setPositiveButton("Resume", (dialog, which) -> runDownload(account, saved, false, back))
                        .setNegativeButton("Back", (dialog, which) -> back.run()));
                return;
            }
            CancellationSignal request = new CancellationSignal();
            pending = request;
            button.setEnabled(false);
            indexReader.execute(() -> {
                List<PhotosMediaFolders.Folder> folders;
                try {
                    folders = PhotosMediaFolders.existing(activity.getContentResolver(), request);
                } catch (RuntimeException error) {
                    if (!request.isCanceled()) report("Device folders", error);
                    folders = null;
                }
                List<PhotosMediaFolders.Folder> found = folders;
                activity.runOnUiThread(() -> {
                    if (pending != request) return;
                    pending = null;
                    button.setEnabled(true);
                    if (request.isCanceled() || !currentAccount(account)) return;
                    if (found == null) {
                        message("Could not read device folders.");
                        back.run();
                        return;
                    }
                    showFolders(account, name, items, found, back);
                });
            });
        }

        private void showFolders(int account, String name, List<CloudCameraIndex.Item> items,
                                 List<PhotosMediaFolders.Folder> folders, Runnable back) {
            if (!currentAccount(account)) return;
            boolean camera = items.get(0).source().group().equals(PhotosSourceRules.CAMERA);
            boolean video = items.stream().anyMatch(CloudCameraIndex.Item::video);
            List<PhotosMediaFolders.Folder> ordered = new ArrayList<>(folders);
            var config = bindings.settings;
            String preferred = config == null ? "" : camera ? config.cameraFolder()
                    : "WhatsApp".equals(name) ? config.whatsappFolder()
                    : PhotosSourceRules.VIDEOS.equals(name) ? config.videosFolder() : "";
            ordered.sort(Comparator.comparingInt(folder -> {
                if (folder.volume().equals(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                        && folder.path().equalsIgnoreCase(preferred)) return 0;
                return recommended(folder, name, camera, video) ? 1 : 2;
            }));
            String[] names = ordered.stream().map(folder -> folder.label() + "\n" + folder.detail())
                    .toArray(String[]::new);
            show(new AlertDialog.Builder(activity).setTitle("Choose device collection")
                    .setItems(names, (dialog, which) -> confirmDownload(account, name, items, ordered.get(which),
                            () -> showFolders(account, name, items, folders, back), back))
                    .setPositiveButton("Create collection", (dialog, which) -> createFolder(account, name, items,
                            camera, video, () -> showFolders(account, name, items, folders, back), back))
                    .setNegativeButton("Back", (dialog, which) -> back.run()));
        }

        private boolean recommended(PhotosMediaFolders.Folder folder, String name, boolean camera, boolean video) {
            if (camera) return folder.path().equalsIgnoreCase("DCIM/Camera/");
            if ("WhatsApp".equals(name)) return folder.label().equalsIgnoreCase(video ? "WhatsApp Video" : "WhatsApp Images");
            return folder.label().equalsIgnoreCase(name);
        }

        private void createFolder(int account, String name, List<CloudCameraIndex.Item> items, boolean camera,
                                  boolean video, Runnable back, Runnable done) {
            if (!currentAccount(account)) return;
            EditText entry = new EditText(activity);
            entry.setSingleLine();
            entry.setText(PhotosMediaFolders.safeName(name));
            AlertDialog dialog = new AlertDialog.Builder(activity).setTitle("New device collection")
                    .setMessage("Folder name").setView(entry).setPositiveButton("Continue", null)
                    .setNegativeButton("Back", (unused, which) -> back.run()).show();
            track(dialog);
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(unused -> {
                if (!currentAccount(account)) return;
                try {
                    var folder = PhotosMediaFolders.create(entry.getText().toString(), camera, video);
                    dialog.dismiss();
                    confirmDownload(account, name, items, folder, back, done);
                } catch (IllegalArgumentException error) {
                    entry.setError("Enter a folder name without path separators or special characters.");
                }
            });
        }

        private void confirmDownload(int account, String name, List<CloudCameraIndex.Item> items,
                                     PhotosMediaFolders.Folder folder, Runnable back, Runnable done) {
            if (!currentAccount(account)) return;
            List<String> keys = new ArrayList<>(items.size());
            for (var item : items) keys.add(item.key());
            long bytes = items.stream().mapToLong(CloudCameraIndex.Item::size).filter(size -> size > 0).sum();
            boolean completeEstimate = items.stream().allMatch(item -> item.size() > 0);
            String estimate = bytes <= 0 ? "" : "\n" + (completeEstimate ? "About " : "At least ")
                    + Formatter.formatShortFileSize(activity, bytes);
            AlertDialog.Builder confirm = new AlertDialog.Builder(activity)
                    .setTitle("Download " + name)
                    .setMessage(keys.size() + (keys.size() == 1 ? " item" : " items") + "\n" + folder.detail() + estimate
                            + "\n\nDownloads follow this folder’s backup setting.")
                    .setPositiveButton("Download", (dialog, which) -> runDownload(account,
                            new PhotosSourceDownloads.Job(name, folder, keys), false, done))
                    .setNegativeButton("Back", (dialog, which) -> back.run());
            if (keys.size() > 1) confirm.setNeutralButton("Download first item", (dialog, which) -> runDownload(account,
                    new PhotosSourceDownloads.Job(name, folder, keys.subList(0, 1)), false, done));
            show(confirm);
        }

        private void runDownload(int account, PhotosSourceDownloads.Job job, boolean skip, Runnable back) {
            if (!currentAccount(account)) return;
            if (!bindings.backgroundReady) {
                runForegroundDownload(account, job, skip, back);
                return;
            }
            try {
                if (!bindings.background.schedule(account, job, skip)) {
                    message("Android could not start a background download. Try Resume download from Sources.");
                    back.run();
                    return;
                }
            } catch (IOException | JSONException | RuntimeException error) {
                report("Schedule background download", error);
                message("Could not start the background download. Try Resume download from Sources.");
                back.run();
                return;
            }
            AlertDialog dialog = new AlertDialog.Builder(activity).setTitle("Download " + job.name)
                    .setMessage(job.folder.detail() + "\nWaiting for Android to start the transfer…")
                    .setNegativeButton("Pause", null)
                    .setPositiveButton("Run in background", null).show();
            shown = dialog;
            Consumer<PhotosSourceDownloads.Progress> observer = progress -> {
                if (!dialog.isShowing()) return;
                String counts = downloadCounts(progress);
                if (!progress.stopped()) {
                    dialog.setMessage(job.folder.detail() + "\n" + counts);
                    return;
                }
                dialog.dismiss();
                showDownloadResult(account, job, progress, counts, back);
            };
            dialog.setOnDismissListener(unused -> {
                clearDialog(dialog);
                bindings.background.removeObserver(observer);
            });
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(unused -> {
                dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(false);
                bindings.background.pause(account);
            });
            bindings.background.observe(account, observer);
        }

        private String downloadCounts(PhotosSourceDownloads.Progress progress) {
            return progress.done() + " saved · " + progress.skipped() + " skipped · " + progress.total() + " total";
        }

        private void runForegroundDownload(int account, PhotosSourceDownloads.Job job, boolean skip, Runnable back) {
            if (!currentAccount(account) || downloadSignal != null) return;
            CancellationSignal signal = new CancellationSignal();
            AlertDialog dialog = new AlertDialog.Builder(activity).setTitle("Download " + job.name)
                    .setMessage(job.folder.detail() + "\nPreparing…").setNegativeButton("Pause", null).show();
            shown = dialog;
            dialog.setOnDismissListener(unused -> {
                clearDialog(dialog);
                signal.cancel();
            });
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(unused -> {
                dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(false);
                signal.cancel();
            });
            downloadSignal = signal;
            indexReader.execute(() -> bindings.downloads.run(account, job, signal, skip, progress ->
                    activity.runOnUiThread(() -> {
                        if (progress.stopped() && downloadSignal == signal) downloadSignal = null;
                        bindings.queueStatus(progress.stopped() ? progress.finished() ? "complete" : "paused" : "running", progress);
                        if (!dialog.isShowing() || !currentAccount(account)) return;
                        String counts = downloadCounts(progress);
                        if (!progress.stopped()) {
                            dialog.setMessage(job.folder.detail() + "\n" + counts);
                            return;
                        }
                        dialog.dismiss();
                        showDownloadResult(account, job, progress, counts, back);
                    })));
        }

        private void showDownloadResult(int account, PhotosSourceDownloads.Job job,
                                        PhotosSourceDownloads.Progress progress, String counts, Runnable back) {
            if (!currentAccount(account)) return;
            AlertDialog.Builder result = new AlertDialog.Builder(activity)
                    .setTitle(progress.finished() ? "Download complete" : "Download paused")
                    .setMessage(job.folder.detail() + "\n" + counts
                            + (progress.problem() == null ? "" : "\n\n" + progress.problem()))
                    .setNegativeButton("Back", (dialog, which) -> back.run());
            if (!progress.finished()) {
                result.setPositiveButton("Resume", (dialog, which) -> runDownload(account, job, false, back));
                if (progress.problem() != null) {
                    result.setNeutralButton("Skip item", (dialog, which) -> runDownload(account, job, true, back));
                }
            }
            show(result);
        }

        private void unavailable(Throwable error) {
            report("Sources", error);
            message("Sources is unavailable.");
        }

        private void message(String text) {
            Toast.makeText(activity, text, Toast.LENGTH_SHORT).show();
        }
    }

    private final class PhotosBindings {
        final Method accountProvider;
        final Method accountId;
        final Field viewModel;
        final Field modelAccount;
        final Field topInset;
        final CloudCameraMedia media;
        final PhotosSourceDownloads downloads;
        final PhotosDownloadJob background;
        final Context context;
        volatile PhotosSourcesControl.Config settings;
        boolean backgroundReady;
        private long lastProgressReport;

        PhotosBindings(ClassLoader loader, Class<?> fragment, Context context) throws ReflectiveOperationException {
            this.context = context;
            Class<?> collectionsModel = Class.forName("xsu", false, loader);
            Class<?> accountService = Class.forName("cboe", false, loader);
            accountProvider = fragment.getDeclaredMethod("bE");
            accountProvider.setAccessible(true);
            accountId = accountService.getMethod("d");
            viewModel = accessibleField(fragment, "f");
            modelAccount = accessibleField(collectionsModel, "f");
            topInset = accessibleField(fragment, "ao");
            media = new CloudCameraMedia(loader);
            downloads = new PhotosSourceDownloads(context, media);
            background = new PhotosDownloadJob(context, downloads, this::queueStatus);
        }

        boolean enabled() {
            var config = settings;
            return config != null && config.enabled();
        }

        void refreshSettings() {
            try {
                Bundle values = context.getContentResolver().call(PhotosSourcesControl.URI, "settings", null, null);
                settings = values == null ? null : PhotosSourcesControl.Config.from(values);
            } catch (RuntimeException error) {
                settings = null;
                report("Wirehelm Sources settings", error);
            }
        }

        void queueStatus(String state, PhotosSourceDownloads.Progress progress) {
            long now = SystemClock.elapsedRealtime();
            if ("running".equals(state) && now - lastProgressReport < 750) return;
            lastProgressReport = now;
            controlWorker.execute(() -> reportStatus(state, progress));
        }

        void reportStatus(String state, PhotosSourceDownloads.Progress progress) {
            Bundle values = new Bundle();
            values.putBoolean("backgroundReady", backgroundReady);
            if (progress != null) {
                values.putString("downloadState", state);
                values.putInt("done", progress.done());
                values.putInt("skipped", progress.skipped());
                values.putInt("total", progress.total());
            }
            try {
                context.getContentResolver().call(PhotosSourcesControl.URI, "status", null, values);
            } catch (RuntimeException error) {
                report("Wirehelm Sources status", error);
            }
        }
    }

    private static Field accessibleField(Class<?> type, String name) throws NoSuchFieldException {
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static int viewId(Activity activity, String name) {
        return activity.getResources().getIdentifier(name, "id", PHOTOS);
    }

    private static void updateTop(View view, int margin) {
        ViewGroup.MarginLayoutParams params = (ViewGroup.MarginLayoutParams) view.getLayoutParams();
        if (params.topMargin == margin) return;
        params.topMargin = margin;
        view.setLayoutParams(params);
    }

    private static void report(String action, Throwable error) {
        // Native exceptions may contain a photo key or other account data.
        Throwable cause = error.getCause();
        Log.w(TAG, action + " failed (" + (cause == null ? error : cause).getClass().getSimpleName() + ")");
    }
}
