package com.nodecockpit.customization;

import android.content.Context;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.os.Handler;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.Switch;
import android.widget.TextView;

/** Displays bulb controls in the existing panel window. All SSH work runs in Wirehelm. */
final class EdgeBulbControls implements EdgeControlPage {
    private static final long SLIDER_INTERVAL_MS = 120;

    final LinearLayout view;
    private final Context context;
    private final Handler main;
    private final EdgeControlRequest connection;
    private final TextView status, mode;
    private final Switch power;
    private final Slider brightness, warmth, hue, saturation;
    private final Runnable send = this::sendPending;
    private String pendingMethod;
    private Bundle pending;
    private boolean closed, inflight, syncing, color;
    private int whiteBrightness = 100, colorBrightness = 100, temperature = 50;
    private int hueDegrees, colorSaturation = 100;
    private String error;
    private boolean connected;
    private Integer foregroundInk;

    EdgeBulbControls(Context context, Handler main, boolean configured) {
        this.context = context;
        this.main = main;
        connection = configured ? new EdgeControlRequest(context, main) : null;
        view = new LinearLayout(context);
        view.setOrientation(LinearLayout.VERTICAL);
        status = text(12);
        status.setMinLines(1);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        view.addView(status);
        power = new Switch(context);
        power.setText("Power");
        power.setMinHeight(dp(48));
        view.addView(power, new LinearLayout.LayoutParams(-1, -2));
        power.setOnCheckedChangeListener((button, on) -> {
            if (syncing) return;
            Bundle payload = new Bundle();
            payload.putBoolean("on", on);
            request("power", payload);
        });
        mode = text(13);
        mode.setMinHeight(dp(48));
        mode.setGravity(Gravity.CENTER_VERTICAL);
        android.util.TypedValue ripple = new android.util.TypedValue();
        if (context.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, ripple, true)) {
            mode.setBackgroundResource(ripple.resourceId);
        }
        mode.setFocusable(true);
        mode.setOnClickListener(view -> {
            color = !color;
            render();
            queueAppearance(true);
        });
        view.addView(mode, new LinearLayout.LayoutParams(-1, -2));
        brightness = new Slider("Brightness", 1, 100, "%", value -> {
            if (color) colorBrightness = value; else whiteBrightness = value;
        });
        warmth = new Slider("White temperature", 0, 100, "%", value -> temperature = value);
        hue = new Slider("Hue", 0, 359, "°", value -> hueDegrees = value);
        saturation = new Slider("Saturation", 0, 100, "%", value -> colorSaturation = value);
        if (configured) refresh();
        else {
            error = "Choose a bulb host in Panel actions.";
            render();
        }
    }

    @Override public LinearLayout view() { return view; }

    @Override public void refresh() {
        if (connection != null && !inflight && pending == null) request("read", new Bundle());
    }

    @Override public void setInk(int ink) {
        if (foregroundInk!=null&&foregroundInk==ink) return;
        foregroundInk=ink;
        for (TextView label : new TextView[]{status, power, mode, brightness.label,
                warmth.label, hue.label, saturation.label}) {
            EdgePanelInk.text(label, ink);
        }
        ColorStateList tint = ColorStateList.valueOf(ink);
        ColorStateList inactive = ColorStateList.valueOf((ink & 0x00ffffff) | 0x44000000);
        for (Slider slider : new Slider[]{brightness, warmth, hue, saturation}) {
            slider.seek.setThumbTintList(tint);
            slider.seek.setProgressTintList(tint);
            slider.seek.setProgressBackgroundTintList(inactive);
        }
    }

    @Override public void close() {
        closed = true;
        main.removeCallbacks(send);
        pending = null;
        if (connection != null) connection.close();
    }

    private void queueAppearance(boolean immediately) {
        Bundle payload = new Bundle();
        payload.putInt("brightness", color ? colorBrightness : whiteBrightness);
        if (color) {
            payload.putInt("hue", hueDegrees);
            payload.putInt("saturation", colorSaturation);
        } else payload.putInt("temperature", temperature);
        pending = payload;
        pendingMethod = color ? "color" : "white";
        if (immediately) {
            main.removeCallbacks(send);
            sendPending();
        } else if (!inflight && !main.hasCallbacks(send)) {
            main.postDelayed(send, SLIDER_INTERVAL_MS);
        }
        render();
    }

    private void sendPending() {
        if (closed || inflight || pending == null) return;
        Bundle payload = pending;
        pending = null;
        request(pendingMethod, payload);
    }

    private void request(String method, Bundle payload) {
        if (closed || inflight) return;
        inflight = true;
        error = null;
        render();
        connection.call(method, payload, this::received);
    }

    private void received(Bundle result) {
        if (closed) return;
        inflight = false;
        error = result.getString("error");
        if (error != null) {
            connected = false;
            pending = null;
        } else {
            connected = true;
            syncing = true;
            power.setChecked(result.getBoolean("on"));
            syncing = false;
            if (pending == null) {
                color = result.getBoolean("color");
                whiteBrightness = result.getInt("whiteBrightness", whiteBrightness);
                colorBrightness = result.getInt("colorBrightness", colorBrightness);
                temperature = result.getInt("temperature", temperature);
                hueDegrees = result.getInt("hue", hueDegrees);
                colorSaturation = result.getInt("saturation", colorSaturation);
            }
        }
        render();
        sendPending();
    }

    private void render() {
        status.setText(error != null ? error : !connected ? "Connecting…" : inflight ? "Updating…" : "");
        status.setVisibility(status.length() == 0 ? View.INVISIBLE : View.VISIBLE);
        power.setEnabled(connected && !inflight && pending == null);
        mode.setText(color ? "Switch to white" : "Switch to color");
        mode.setEnabled(connected && !inflight && pending == null);
        mode.setVisibility(connected ? View.VISIBLE : View.GONE);
        brightness.display(color ? colorBrightness : whiteBrightness, connected);
        warmth.display(temperature, connected && !color);
        hue.display(hueDegrees, connected && color);
        saturation.display(colorSaturation, connected && color);
    }

    private TextView text(int size) {
        TextView text = new TextView(context);
        text.setTextSize(size);
        return text;
    }

    private int dp(int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private final class Slider {
        final TextView label;
        final SeekBar seek;
        final LinearLayout group;
        final String name, suffix;

        Slider(String name, int min, int max, String suffix, java.util.function.IntConsumer change) {
            this.name = name;
            this.suffix = suffix;
            group = new LinearLayout(context);
            group.setOrientation(LinearLayout.VERTICAL);
            label = text(12);
            group.addView(label);
            seek = new SeekBar(context);
            seek.setMin(min);
            seek.setMax(max);
            seek.setMinimumHeight(dp(48));
            seek.setContentDescription(name);
            seek.setOnTouchListener((view, event) -> {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN)
                    view.getParent().requestDisallowInterceptTouchEvent(true);
                else if (event.getActionMasked() == MotionEvent.ACTION_UP ||
                         event.getActionMasked() == MotionEvent.ACTION_CANCEL)
                    view.getParent().requestDisallowInterceptTouchEvent(false);
                return false;
            });
            seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
                @Override public void onStartTrackingTouch(SeekBar bar) {}
                @Override public void onStopTrackingTouch(SeekBar bar) {
                    main.removeCallbacks(send);
                    sendPending();
                }
                @Override public void onProgressChanged(SeekBar bar, int value, boolean user) {
                    if (!user) return;
                    change.accept(value);
                    queueAppearance(false);
                }
            });
            group.addView(seek, new LinearLayout.LayoutParams(-1, -2));
            view.addView(group, new LinearLayout.LayoutParams(-1, -2));
        }

        void display(int value, boolean visible) {
            group.setVisibility(visible ? View.VISIBLE : View.GONE);
            if (!visible) return;
            label.setText(name + " · " + value + suffix);
            if (seek.getProgress() != value) seek.setProgress(value);
        }
    }
}
