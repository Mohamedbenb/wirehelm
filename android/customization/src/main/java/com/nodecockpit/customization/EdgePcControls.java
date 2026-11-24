package com.nodecockpit.customization;

import android.app.ActivityOptions;
import android.app.PendingIntent;
import android.content.Context;
import android.content.res.ColorStateList;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

final class EdgePcControls implements EdgeControlPage {
    private enum Action {
        LOCK("Lock", "lock"),
        SLEEP("Sleep", "sleep"),
        LOCK_AND_SLEEP("Lock & sleep", "lockAndSleep"),
        RESTART("Restart", "restart"),
        SHUT_DOWN("Shut down", "shutDown");

        final String label;
        final String id;

        Action(String label, String id) {
            this.label = label;
            this.id = id;
        }
    }

    private final Context context;
    private final EdgeControlRequest connection;
    private final boolean textSize, configured;
    private final Runnable onUnlockOpened;
    private final LinearLayout pane, actions;
    private final TextView status;
    private final List<TextView> labels = new ArrayList<>();
    private boolean busy, ready;
    private String host, device;
    private int foreground;
    private Action confirming;

    EdgePcControls(Context context, Handler main, boolean textSize, boolean configured, Runnable onUnlockOpened) {
        this.context = context;
        this.textSize = textSize;
        this.configured = configured;
        this.onUnlockOpened = onUnlockOpened;
        connection = configured ? new EdgeControlRequest(context, main) : null;
        pane = column();
        status = text("Choose a CachyOS PC in Panel actions.", 12);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        pane.addView(status, new LinearLayout.LayoutParams(-1, -2));
        actions = column();
        pane.addView(actions, new LinearLayout.LayoutParams(-1, -2));
        refresh();
    }

    @Override public LinearLayout view() { return pane; }

    @Override public void refresh() {
        request(textSize ? "textRead" : "pcRead", new Bundle(), null);
    }

    @Override public void setInk(int ink) {
        if (foreground == ink) return;
        foreground = ink;
        for (TextView label : labels) EdgePanelInk.text(label, ink);
        for (int i = 0; i < actions.getChildCount(); i++)
            if (actions.getChildAt(i) instanceof SeekBar slider) slider.setProgressTintList(ColorStateList.valueOf(ink));
    }

    @Override public void close() {
        if (connection != null) connection.close();
    }

    private void request(String method, Bundle payload, Action action) {
        if (!configured || busy) return;
        busy = true;
        confirming = null;
        status.setText(action != null ? "Sending " + action.label + "…" : "Connecting…");
        clearActions();
        connection.call(method, payload, result -> {
            busy = false;
            String error = result.getString("error");
            ready = result.getBoolean("ready");
            if (error != null || !ready) {
                status.setText(error != null ? error : "The PC did not return a control state.");
                return;
            }
            host = result.getString("deviceName", "PC");
            if (method.equals("pcRead")) device = result.getString("device");
            if (textSize) {
                double size = result.getDouble("size", Double.NaN);
                if (!Double.isFinite(size)) {
                    status.setText("The PC did not report its text size.");
                    return;
                }
                status.setText(host + " · " + points(size));
                showTextSize(size, result.getBoolean("sizesMatch"));
            } else if (action == null) {
                showPower();
            } else {
                status.setText(action.label + " accepted by " + host + ".");
                if (action == Action.LOCK) showPowerButtons();
            }
        });
    }

    private void showPower() {
        status.setText(host);
        showPowerButtons();
    }

    private void showPowerButtons() {
        clearActions();
        for (Action action : Action.values()) {
            addButton(action.label, () -> confirmPower(action));
            if (action == Action.LOCK && device != null) addButton("Unlock PC", this::unlockPc);
        }
    }

    @SuppressWarnings("deprecation")
    private void unlockPc() {
        if (!ready || busy || device == null) return;
        busy = true;
        Bundle args = new Bundle();
        args.putString("device", device);
        connection.call("pcUnlockIntent", args, result -> {
            busy = false;
            String error = result.getString("error");
            if (error != null) {
                status.setText(error);
                return;
            }
            PendingIntent intent = result.getParcelable("unlockIntent");
            if (intent == null) {
                status.setText("PC unlock is unavailable. Refresh to retry.");
                return;
            }
            try {
                if (Build.VERSION.SDK_INT >= 34) {
                    ActivityOptions options = ActivityOptions.makeBasic();
                    options.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED);
                    intent.send(context, 0, null, null, null, null, options.toBundle());
                } else {
                    intent.send();
                }
                onUnlockOpened.run();
            } catch (PendingIntent.CanceledException | SecurityException ignored) {
                status.setText("Could not open PC unlock. Refresh to retry.");
            }
        });
    }

    private void confirmPower(Action action) {
        if (!ready || busy) return;
        confirming = action;
        clearActions();
        status.setText(action.label + " · " + host + "?");
        addButton("Confirm " + action.label, () -> {
            if (confirming != action) return;
            Bundle payload = new Bundle();
            payload.putString("action", action.id);
            request("pcPower", payload, action);
        });
        addButton("Cancel", () -> {
            confirming = null;
            showPower();
        });
    }

    private void showTextSize(double original, boolean sizesMatch) {
        clearActions();
        SeekBar slider = new SeekBar(context);
        slider.setMin(12);
        slider.setMax(64);
        slider.setProgress((int)Math.round(Math.max(6, Math.min(32, original)) * 2));
        slider.setMinimumHeight(dp(48));
        slider.setContentDescription("Text size");
        if (foreground != 0) slider.setProgressTintList(ColorStateList.valueOf(foreground));
        slider.setOnTouchListener((v, event) -> {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN) v.getParent().requestDisallowInterceptTouchEvent(true);
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL)
                v.getParent().requestDisallowInterceptTouchEvent(false);
            return false;
        });

        TextView value = text(points(slider.getProgress() / 2d), 16);
        actions.addView(value);
        actions.addView(slider, new LinearLayout.LayoutParams(-1, -2));
        TextView apply = addButton("Apply text size", () -> {
            Bundle payload = new Bundle();
            payload.putInt("halfPoints", slider.getProgress());
            request("textApply", payload, null);
        });
        apply.setEnabled(!sizesMatch || slider.getProgress() / 2d != original);
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onStartTrackingTouch(SeekBar bar) {}
            @Override public void onStopTrackingTouch(SeekBar bar) {}
            @Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                value.setText(points(progress / 2d));
                apply.setEnabled(!sizesMatch || progress / 2d != original);
            }
        });
        addButton("Select 10 pt", () -> slider.setProgress(20));
    }

    private String points(double value) {
        return (value == Math.rint(value) ? Long.toString(Math.round(value)) : Double.toString(value)) + " pt";
    }

    private void clearActions() {
        actions.removeAllViews();
        labels.removeIf(label -> label != status);
    }

    private TextView addButton(String label, Runnable clicked) {
        TextView button = text(label, 13);
        button.setMinHeight(dp(48));
        button.setGravity(Gravity.CENTER_VERTICAL);
        button.setFocusable(true);
        android.util.TypedValue background = new android.util.TypedValue();
        if (context.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, background, true))
            button.setBackgroundResource(background.resourceId);
        if (foreground != 0) EdgePanelInk.text(button, foreground);
        button.setOnClickListener(v -> clicked.run());
        actions.addView(button, new LinearLayout.LayoutParams(-1, -2));
        return button;
    }

    private TextView text(String value, int size) {
        TextView label = new TextView(context);
        label.setText(value);
        label.setTextSize(size);
        if (foreground != 0) EdgePanelInk.text(label, foreground);
        labels.add(label);
        return label;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(context);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private int dp(int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
