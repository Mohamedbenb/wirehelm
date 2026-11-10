package com.nodecockpit.customization;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

/** A screen preview and standard controls for editing a freeform task's bounds. */
final class EdgeWindowLayout extends LinearLayout {
    private static final int STEPS = 1000;
    private final Rect screen;
    private final int minWidth;
    private final int minHeight;
    private final SeekBar horizontal;
    private final SeekBar vertical;
    private final SeekBar width;
    private final SeekBar height;
    private final View preview;

    EdgeWindowLayout(Context context, Rect screen, Rect initial) {
        super(context);
        this.screen = new Rect(screen);
        minWidth = Math.max(1, Math.min(dp(180), Math.min(initial.width(), screen.width())));
        minHeight = Math.max(1, Math.min(dp(180), Math.min(initial.height(), screen.height())));
        setOrientation(VERTICAL);
        TextView hint = new TextView(context);
        hint.setText("Drag the window to move it. Drag the dot to resize.");
        hint.setTextColor(0xFF526075);
        hint.setPadding(0, dp(6), 0, dp(6));
        addView(hint);
        preview = new Preview(context);
        preview.setContentDescription("Window preview");
        addView(preview, new LayoutParams(-1, dp(160)));

        LinearLayout presets = new LinearLayout(context);
        presets.setGravity(Gravity.CENTER);
        addPreset(presets, "Small", .48f, .36f);
        addPreset(presets, "Medium", .64f, .52f);
        addPreset(presets, "Large", .84f, .72f);
        addView(presets, new LayoutParams(-1, -2));

        int initialWidth = Math.min(screen.width(), Math.max(minWidth, initial.width()));
        int initialHeight = Math.min(screen.height(), Math.max(minHeight, initial.height()));
        horizontal = control("Horizontal position", fraction(initial.left - screen.left, screen.width() - initialWidth));
        vertical = control("Vertical position", fraction(initial.top - screen.top, screen.height() - initialHeight));
        width = control("Width", fraction(initialWidth - minWidth, screen.width() - minWidth));
        height = control("Height", fraction(initialHeight - minHeight, screen.height() - minHeight));
    }

    Rect editedBounds() {
        int w = minWidth + offset(width, screen.width() - minWidth);
        int h = minHeight + offset(height, screen.height() - minHeight);
        int x = screen.left + offset(horizontal, screen.width() - w);
        int y = screen.top + offset(vertical, screen.height() - h);
        return new Rect(x, y, x + w, y + h);
    }

    private void addPreset(LinearLayout row, String label, float widthFraction, float heightFraction) {
        Button button = new Button(getContext());
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(v -> {
            Rect old = editedBounds();
            int w = Math.max(minWidth, Math.round(screen.width() * widthFraction));
            int h = Math.max(minHeight, Math.round(screen.height() * heightFraction));
            int x = old.centerX() - w / 2;
            int y = old.centerY() - h / 2;
            setBounds(new Rect(x, y, x + w, y + h));
        });
        row.addView(button, new LayoutParams(0, -2, 1));
    }

    private void setBounds(Rect next) {
        int w = Math.max(minWidth, Math.min(screen.width(), next.width()));
        int h = Math.max(minHeight, Math.min(screen.height(), next.height()));
        width.setProgress(fraction(w - minWidth, screen.width() - minWidth));
        height.setProgress(fraction(h - minHeight, screen.height() - minHeight));
        horizontal.setProgress(fraction(next.left - screen.left, screen.width() - w));
        vertical.setProgress(fraction(next.top - screen.top, screen.height() - h));
        preview.invalidate();
    }

    private SeekBar control(String name, int value) {
        TextView label = new TextView(getContext());
        label.setText(name);
        label.setTextColor(0xFF10161D);
        addView(label);
        SeekBar control = new SeekBar(getContext());
        control.setContentDescription(name);
        control.setMax(STEPS);
        control.setProgress(value);
        control.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) { preview.invalidate(); }
            @Override public void onStartTrackingTouch(SeekBar bar) {}
            @Override public void onStopTrackingTouch(SeekBar bar) {}
        });
        addView(control, new LayoutParams(-1, dp(38)));
        return control;
    }

    private static int fraction(int value, int range) {
        return range <= 0 ? 0 : Math.max(0, Math.min(STEPS, Math.round((float) STEPS * value / range)));
    }

    private static int offset(SeekBar control, int range) {
        return Math.round(range * control.getProgress() / (float) STEPS);
    }

    private final class Preview extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private Rect start;
        private float startX;
        private float startY;
        private boolean resize;

        Preview(Context context) { super(context); }

        private float scale() {
            return Math.min((float) getWidth() / screen.width(), (float) getHeight() / screen.height());
        }

        private RectF pixels(Rect bounds, float scale) {
            float x = (getWidth() - screen.width() * scale) / 2f - screen.left * scale;
            float y = (getHeight() - screen.height() * scale) / 2f - screen.top * scale;
            return new RectF(x + bounds.left * scale, y + bounds.top * scale,
                    x + bounds.right * scale, y + bounds.bottom * scale);
        }

        @Override protected void onDraw(Canvas canvas) {
            float scale = scale();
            paint.setColor(0xFFCCD5E2);
            canvas.drawRoundRect(pixels(screen, scale), dp(5), dp(5), paint);
            RectF box = pixels(editedBounds(), scale);
            paint.setColor(0xFF285B92);
            canvas.drawRoundRect(box, dp(3), dp(3), paint);
            paint.setColor(0xFFFFFFFF);
            canvas.drawCircle(box.right - dp(6), box.bottom - dp(6), dp(3), paint);
        }

        @Override public boolean onTouchEvent(MotionEvent event) {
            float scale = scale();
            if (scale <= 0) return false;
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    Rect initial = editedBounds();
                    RectF box = pixels(initial, scale);
                    startX = event.getX();
                    startY = event.getY();
                    resize = Math.hypot(startX - box.right + dp(6), startY - box.bottom + dp(6)) <= dp(15);
                    if (!resize && !box.contains(startX, startY)) return false;
                    start = initial;
                    getParent().requestDisallowInterceptTouchEvent(true);
                    return true;
                case MotionEvent.ACTION_MOVE:
                    if (start == null) return false;
                    int dx = Math.round((event.getX() - startX) / scale);
                    int dy = Math.round((event.getY() - startY) / scale);
                    Rect next = new Rect(start);
                    if (resize) {
                        next.right = Math.min(screen.right, Math.max(next.left + minWidth, next.right + dx));
                        next.bottom = Math.min(screen.bottom, Math.max(next.top + minHeight, next.bottom + dy));
                    } else {
                        next.offset(dx, dy);
                    }
                    setBounds(next);
                    return true;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (start == null) return false;
                    start = null;
                    getParent().requestDisallowInterceptTouchEvent(false);
                    return true;
                default:
                    return start != null;
            }
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
