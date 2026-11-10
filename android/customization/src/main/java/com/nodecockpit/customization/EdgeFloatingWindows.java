package com.nodecockpit.customization;

import android.app.ActivityManager;
import android.app.ActivityOptions;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.UserHandle;
import android.util.Log;
import android.view.Display;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/** Requests Android's native freeform tasks and returns to existing tasks by ID. */
final class EdgeFloatingWindows {
    private static final int FREEFORM = 5;
    private static final int FULLSCREEN = 1;
    private final Context context;
    private final ActivityManager activityManager;
    private final TaskApi api;
    private final OrganizerApi organizer;
    private final PinApi pinApi;
    private String state = "idle";

    EdgeFloatingWindows(Context context) {
        this.context = context;
        activityManager = context.getSystemService(ActivityManager.class);
        api = bindApi(context);
        organizer = api == null ? null : bindOrganizer(context);
        pinApi = organizer == null ? null : bindPinApi(organizer);
    }

    private static TaskApi bindApi(Context context) {
        if (!context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_FREEFORM_WINDOW_MANAGEMENT)
                || context.checkSelfPermission("android.permission.START_TASKS_FROM_RECENTS")
                != PackageManager.PERMISSION_GRANTED) return null;
        try {
            return new TaskApi();
        } catch (ReflectiveOperationException | RuntimeException error) {
            Log.w("WirehelmWindows", "Native freeform API unavailable", error);
            return null;
        }
    }

    boolean available() {
        return api != null && activityManager != null;
    }

    private static OrganizerApi bindOrganizer(Context context) {
        if (context.checkSelfPermission("android.permission.MANAGE_ACTIVITY_TASKS")
                != PackageManager.PERMISSION_GRANTED) return null;
        try {
            return new OrganizerApi();
        } catch (ReflectiveOperationException | RuntimeException error) {
            Log.w("WirehelmWindows", "Window arrangement unavailable", error);
            return null;
        }
    }

    boolean canArrange() {
        return organizer != null;
    }

    private static PinApi bindPinApi(OrganizerApi organizer) {
        try {
            return new PinApi(organizer.transactionType);
        } catch (ReflectiveOperationException | RuntimeException error) {
            Log.w("WirehelmWindows", "Always-on-top unavailable", error);
            return null;
        }
    }

    boolean canPin() {
        return pinApi != null;
    }

    private List<ActivityManager.RunningTaskInfo> tasks() throws ReflectiveOperationException {
        List<ActivityManager.RunningTaskInfo> windows = new ArrayList<>();
        int currentUser = activeUser();
        for (ActivityManager.RunningTaskInfo task : activityManager.getRunningTasks(64)) {
            if (task.taskId < 0 || !task.isRunning || task.baseActivity == null
                    || api.userId.getInt(task) != currentUser
                    || api.displayId.getInt(task) != Display.DEFAULT_DISPLAY
                    || (Integer) api.windowingMode.invoke(task) != FREEFORM) continue;
            windows.add(task);
        }
        return windows;
    }

    List<Window> list() throws ReflectiveOperationException {
        List<Window> windows = new ArrayList<>();
        for (ActivityManager.RunningTaskInfo task : tasks()) {
            ComponentName launcher = task.baseIntent == null ? null : task.baseIntent.getComponent();
            boolean pinned = pinApi != null && pinApi.isPinned(task);
            windows.add(new Window(task.taskId, task.baseActivity, launcher, pinned));
        }
        return windows;
    }

    void launch(Intent intent) throws ReflectiveOperationException {
        for (Window window : list()) {
            if (window.matches(intent.getComponent())) {
                resumeTask(window.id);
                return;
            }
        }
        activeUser();
        context.startActivity(new Intent(intent).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), options());
        state = "launch-requested";
    }

    boolean resume(Window selected) throws ReflectiveOperationException {
        if (findTask(selected) == null) return false;
        resumeTask(selected.id);
        return true;
    }

    private ActivityManager.RunningTaskInfo findTask(Window selected) throws ReflectiveOperationException {
        for (ActivityManager.RunningTaskInfo task : tasks()) {
            if (task.taskId == selected.id && selected.base.equals(task.baseActivity)) return task;
        }
        state = "window-closed";
        return null;
    }

    Rect bounds(Window selected) throws ReflectiveOperationException {
        if (findTask(selected) == null) return null;
        return (Rect) organizer.getBounds.invoke(api.getService.invoke(null), selected.id);
    }

    /** Apply window bounds and bring the task forward, or lower it without ending it. */
    boolean arrange(Window selected, Rect bounds) throws ReflectiveOperationException {
        ActivityManager.RunningTaskInfo task = findTask(selected);
        if (task == null) return false;
        Object transaction = organizer.transactionType.getConstructor().newInstance();
        Object token = organizer.token.get(task);
        if (bounds != null) {
            organizer.setBounds.invoke(transaction, token, bounds);
        } else if (pinApi != null && pinApi.isPinned(task)) {
            pinApi.setAlwaysOnTop.invoke(transaction, token, false);
        }
        organizer.reorder.invoke(transaction, token, bounds != null);
        organizer.apply.invoke(organizer.owner, transaction);
        state = bounds == null ? "minimized" : "arranged";
        return true;
    }

    boolean setPinned(Window selected, boolean pinned) throws ReflectiveOperationException {
        ActivityManager.RunningTaskInfo task = findTask(selected);
        if (task == null) return false;
        Object transaction = organizer.transactionType.getConstructor().newInstance();
        Object token = organizer.token.get(task);
        pinApi.setAlwaysOnTop.invoke(transaction, token, pinned);
        organizer.apply.invoke(organizer.owner, transaction);
        state = pinned ? "pinned" : "unpinned";
        return true;
    }

    boolean fullscreen(Window selected) throws ReflectiveOperationException {
        ActivityManager.RunningTaskInfo task = findTask(selected);
        if (task == null) return false;
        Object transaction = organizer.transactionType.getConstructor().newInstance();
        Object token = organizer.token.get(task);
        if (pinApi != null && pinApi.isPinned(task)) {
            pinApi.setAlwaysOnTop.invoke(transaction, token, false);
        }
        organizer.setBounds.invoke(transaction, token, new Rect());
        organizer.setWindowingMode.invoke(transaction, token, FULLSCREEN);
        organizer.reorder.invoke(transaction, token, true);
        organizer.apply.invoke(organizer.owner, transaction);
        state = "fullscreen";
        return true;
    }

    private Bundle options() throws ReflectiveOperationException {
        ActivityOptions options = ActivityOptions.makeBasic().setLaunchDisplayId(Display.DEFAULT_DISPLAY);
        api.setWindowingMode.invoke(options, FREEFORM);
        return options.toBundle();
    }

    private int activeUser() throws ReflectiveOperationException {
        int user = (Integer) api.currentUser.invoke(null);
        int processUser = (Integer) api.userIdentifier.invoke(android.os.Process.myUserHandle());
        if (user != processUser) throw new IllegalStateException("The active Android user changed");
        return user;
    }

    private void resumeTask(int id) throws ReflectiveOperationException {
        Object service = api.getService.invoke(null);
        int result = (Integer) api.startFromRecents.invoke(service, id, options());
        if (result < 0) throw new IllegalStateException("Android rejected the window: " + result);
        state = "restored";
    }

    void reportFailure(Exception error) {
        state = "failed";
        Log.w("WirehelmWindows", "Floating window action failed", error);
    }

    String diagnostics() {
        return available() ? state : "unavailable";
    }

    static final class Window {
        final int id;
        final ComponentName base;
        final ComponentName launcher;
        final boolean pinned;

        Window(int id, ComponentName base, ComponentName launcher, boolean pinned) {
            this.id = id;
            this.base = base;
            this.launcher = launcher;
            this.pinned = pinned;
        }

        boolean matches(ComponentName component) {
            return component != null && (component.equals(base) || component.equals(launcher));
        }
    }

    private static final class TaskApi {
        final Method setWindowingMode;
        final Method getService;
        final Method startFromRecents;
        final Method currentUser;
        final Method userIdentifier;
        final Method windowingMode;
        final Field userId;
        final Field displayId;

        TaskApi() throws ReflectiveOperationException {
            setWindowingMode = ActivityOptions.class.getMethod("setLaunchWindowingMode", int.class);
            getService = Class.forName("android.app.ActivityTaskManager").getMethod("getService");
            startFromRecents = getService.getReturnType().getMethod("startActivityFromRecents", int.class, Bundle.class);
            currentUser = ActivityManager.class.getMethod("getCurrentUser");
            userIdentifier = UserHandle.class.getMethod("getIdentifier");
            Class<ActivityManager.RunningTaskInfo> task = ActivityManager.RunningTaskInfo.class;
            windowingMode = task.getMethod("getWindowingMode");
            userId = task.getField("userId");
            displayId = task.getField("displayId");
        }
    }

    private static final class OrganizerApi {
        final Class<?> transactionType;
        final Object owner;
        final Field token;
        final Method getBounds;
        final Method setBounds;
        final Method setWindowingMode;
        final Method reorder;
        final Method apply;

        OrganizerApi() throws ReflectiveOperationException {
            transactionType = Class.forName("android.window.WindowContainerTransaction");
            Class<?> organizerType = Class.forName("android.window.WindowOrganizer");
            Class<?> tokenType = Class.forName("android.window.WindowContainerToken");
            owner = organizerType.getConstructor().newInstance();
            token = ActivityManager.RunningTaskInfo.class.getField("token");
            getBounds = Class.forName("android.app.IActivityTaskManager").getMethod("getTaskBounds", int.class);
            setBounds = transactionType.getMethod("setBounds", tokenType, Rect.class);
            setWindowingMode = transactionType.getMethod("setWindowingMode", tokenType, int.class);
            reorder = transactionType.getMethod("reorder", tokenType, boolean.class);
            apply = organizerType.getMethod("applyTransaction", transactionType);
        }
    }

    private static final class PinApi {
        final Field configuration;
        final Field windowConfiguration;
        final Method isAlwaysOnTop;
        final Method setAlwaysOnTop;

        PinApi(Class<?> transactionType) throws ReflectiveOperationException {
            configuration = ActivityManager.RunningTaskInfo.class.getField("configuration");
            windowConfiguration = configuration.getType().getField("windowConfiguration");
            isAlwaysOnTop = windowConfiguration.getType().getMethod("isAlwaysOnTop");
            Class<?> tokenType = Class.forName("android.window.WindowContainerToken");
            setAlwaysOnTop = transactionType.getMethod("setAlwaysOnTop", tokenType, boolean.class);
        }

        boolean isPinned(ActivityManager.RunningTaskInfo task) throws ReflectiveOperationException {
            return (Boolean) isAlwaysOnTop.invoke(windowConfiguration.get(configuration.get(task)));
        }
    }
}
