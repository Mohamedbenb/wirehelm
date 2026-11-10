package com.nodecockpit.customization;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;

/** Small line icons for edge panel controls. The existing edge ink supplies their color. */
final class EdgePanelIcon extends Drawable {
    enum Kind { EDIT, SCREENSHOT, SETTINGS, WINDOWS, ADD, BACK, CANCEL, SAVE, MORE }

    private final Kind kind;
    private final ConstantState state;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();

    EdgePanelIcon(Kind kind) {
        this.kind = kind;
        state = new ConstantState() {
            @Override public Drawable newDrawable() { return new EdgePanelIcon(kind); }
            @Override public int getChangingConfigurations() { return 0; }
        };
        paint.setColor(Color.WHITE);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1.8f);
        paint.setStrokeCap(Paint.Cap.ROUND);
        paint.setStrokeJoin(Paint.Join.ROUND);
    }

    @Override public void draw(Canvas canvas) {
        Rect bounds = getBounds();
        float size = Math.min(bounds.width(), bounds.height());
        int save = canvas.save();
        canvas.translate(bounds.exactCenterX() - size / 2f, bounds.exactCenterY() - size / 2f);
        canvas.scale(size / 24f, size / 24f);
        switch (kind) {
            case EDIT:
                line(canvas, 4, 20, 5.5f, 14.5f, 16.5f, 3.5f, 20.5f, 7.5f, 9.5f, 18.5f, 4, 20);
                line(canvas, 14.5f, 5.5f, 18.5f, 9.5f);
                break;
            case SCREENSHOT:
                line(canvas, 3.5f, 8, 3.5f, 4, 8, 4);
                line(canvas, 16, 4, 20.5f, 4, 20.5f, 8);
                line(canvas, 20.5f, 16, 20.5f, 20, 16, 20);
                line(canvas, 8, 20, 3.5f, 20, 3.5f, 16);
                canvas.drawCircle(12, 12, 3.2f, paint);
                break;
            case SETTINGS:
                canvas.drawCircle(12, 12, 2.8f, paint);
                line(canvas, 15, 6, 14, 4, 10, 4, 9, 6, 7, 7, 4.8f, 7, 3.2f, 10, 4.7f, 12, 4.7f, 13.8f,
                        3.2f, 15.5f, 4.8f, 18, 7.2f, 18, 9, 19, 10, 21, 14, 21, 15, 19,
                        16.8f, 18, 19.2f, 18, 20.8f, 15.5f, 19.3f, 13.8f, 19.3f, 12,
                        20.8f, 10, 19.2f, 7, 17, 7, 15, 6);
                break;
            case WINDOWS:
                line(canvas, 3.5f, 14, 3.5f, 4.5f, 16.5f, 4.5f, 16.5f, 7.5f);
                canvas.drawRoundRect(7.5f, 8, 21, 19.5f, 1.8f, 1.8f, paint);
                line(canvas, 8.5f, 11, 20, 11);
                break;
            case ADD:
                line(canvas, 12, 5, 12, 19);
                line(canvas, 5, 12, 19, 12);
                break;
            case BACK:
                line(canvas, 11, 5, 4, 12, 11, 19);
                line(canvas, 4, 12, 20, 12);
                break;
            case CANCEL:
                line(canvas, 6, 6, 18, 18);
                line(canvas, 18, 6, 6, 18);
                break;
            case SAVE:
                line(canvas, 4.5f, 12.5f, 9.5f, 17.5f, 19.5f, 6.5f);
                break;
            case MORE:
                paint.setStyle(Paint.Style.FILL);
                for (int y = 6; y <= 18; y += 6) canvas.drawCircle(12, y, 1.5f, paint);
                paint.setStyle(Paint.Style.STROKE);
                break;
        }
        canvas.restoreToCount(save);
    }

    private void line(Canvas canvas, float... xy) {
        path.reset();
        path.moveTo(xy[0], xy[1]);
        for (int i = 2; i < xy.length; i += 2) path.lineTo(xy[i], xy[i + 1]);
        canvas.drawPath(path, paint);
    }

    @Override public void setAlpha(int alpha) { paint.setAlpha(alpha); invalidateSelf(); }
    @Override public void setColorFilter(ColorFilter filter) { paint.setColorFilter(filter); invalidateSelf(); }
    @Override public int getIntrinsicWidth() { return 24; }
    @Override public int getIntrinsicHeight() { return 24; }
    @Override public ConstantState getConstantState() { return state; }
    @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
}
