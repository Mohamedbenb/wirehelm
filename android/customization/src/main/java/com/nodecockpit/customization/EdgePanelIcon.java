package com.nodecockpit.customization;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;

/** Panel glyphs rendered as vector paths at the display's draw scale. */
final class EdgePanelIcon extends Drawable {
    enum Kind { EDIT, SCREENSHOT, SETTINGS, WINDOWS, ADD, BACK, CANCEL, SAVE, MORE, CLIPBOARD, REFRESH, BULB, POWER, TEXT, KEYBOARD }

    private static final float VIEWPORT = 24f;
    private final ConstantState state;
    private final Path glyph;
    private final Paint foreground = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint outline = new Paint(Paint.ANTI_ALIAS_FLAG);
    private int ink = Color.WHITE;
    private int alpha = 255;

    EdgePanelIcon(Kind kind) {
        state = new ConstantState() {
            @Override public Drawable newDrawable() { return new EdgePanelIcon(kind); }
            @Override public int getChangingConfigurations() { return 0; }
        };
        glyph = createGlyph(kind);
        outline.setStyle(Paint.Style.FILL_AND_STROKE);
        outline.setStrokeWidth(1.1f);
        outline.setStrokeJoin(Paint.Join.ROUND);
        updatePaints();
    }

    void setInk(int color) {
        if (ink == color) return;
        ink = color;
        updatePaints();
        invalidateSelf();
    }

    private void updatePaints() {
        foreground.setColor(ink);
        foreground.setAlpha(alpha * Color.alpha(ink) / 255);
        // One continuous contour keeps the core stroke crisp on translucent glass.
        outline.setColor(Color.luminance(ink) > .179f ? Color.BLACK : Color.WHITE);
        outline.setAlpha(alpha * 170 / 255);
        outline.setShadowLayer(.85f, 0, .55f, (alpha * 46 / 255) << 24);
    }

    @Override public void draw(Canvas canvas) {
        Rect bounds = getBounds();
        float size = Math.min(bounds.width(), bounds.height());
        if (size <= 0 || alpha == 0) return;
        int save = canvas.save();
        canvas.translate(bounds.exactCenterX() - size / 2, bounds.exactCenterY() - size / 2);
        canvas.scale(size / VIEWPORT, size / VIEWPORT);
        canvas.drawPath(glyph, outline);
        canvas.drawPath(glyph, foreground);
        canvas.restoreToCount(save);
    }

    private static Path createGlyph(Kind kind) {
        Path path = new Path();
        Path.Direction cw = Path.Direction.CW;
        switch (kind) {
            case EDIT:
                line(path, 4, 20, 5.5f, 14.5f, 16.5f, 3.5f, 20.5f, 7.5f, 9.5f, 18.5f, 4, 20);
                line(path, 14.5f, 5.5f, 18.5f, 9.5f);
                break;
            case SCREENSHOT:
                line(path, 3.5f, 8, 3.5f, 4, 8, 4);
                line(path, 16, 4, 20.5f, 4, 20.5f, 8);
                line(path, 20.5f, 16, 20.5f, 20, 16, 20);
                line(path, 8, 20, 3.5f, 20, 3.5f, 16);
                path.addCircle(12, 12, 3.2f, cw);
                break;
            case SETTINGS:
                for (int i = 0; i < 32; i++) {
                    double angle = -Math.PI / 2 + i * Math.PI / 16;
                    float radius = (i % 4 == 1 || i % 4 == 2) ? 8.5f : 6.7f;
                    float x = 12 + (float)Math.cos(angle) * radius;
                    float y = 12 + (float)Math.sin(angle) * radius;
                    if (i == 0) path.moveTo(x, y);
                    else path.lineTo(x, y);
                }
                path.close();
                path.addCircle(12, 12, 2.8f, cw);
                break;
            case CLIPBOARD:
                line(path, 9, 5, 7, 5);
                path.quadTo(5, 5, 5, 7);
                path.lineTo(5, 19);
                path.quadTo(5, 21, 7, 21);
                path.lineTo(17, 21);
                path.quadTo(19, 21, 19, 19);
                path.lineTo(19, 7);
                path.quadTo(19, 5, 17, 5);
                path.lineTo(15, 5);
                path.addRoundRect(9, 3, 15, 7, 1, 1, cw);
                line(path, 9, 11, 15, 11);
                line(path, 9, 15, 15, 15);
                break;
            case WINDOWS:
                line(path, 3.5f, 14, 3.5f, 4.5f, 16.5f, 4.5f, 16.5f, 7.5f);
                path.addRoundRect(7.5f, 8, 21, 19.5f, 1.8f, 1.8f, cw);
                line(path, 8.5f, 11, 20, 11);
                break;
            case BULB:
                path.moveTo(9, 17);
                path.cubicTo(9, 14, 6, 13, 6, 9);
                path.cubicTo(6, 2, 18, 2, 18, 9);
                path.cubicTo(18, 13, 15, 14, 15, 17);
                path.close();
                line(path, 9.5f, 20, 14.5f, 20);
                break;
            case POWER:
                path.addArc(4, 5, 20, 21, -49, 278);
                line(path, 12, 3, 12, 12);
                break;
            case TEXT:
                line(path, 4, 18, 9.5f, 5, 15, 18);
                line(path, 6, 13.5f, 13, 13.5f);
                line(path, 16, 18, 19, 11, 22, 18);
                line(path, 17, 16, 21, 16);
                break;
            case KEYBOARD:
                path.addRoundRect(2, 5, 22, 19, 2, 2, cw);
                for (int x = 6; x <= 18; x += 4) {
                    line(path, x, 9, x + .1f, 9);
                    line(path, x, 12, x + .1f, 12);
                }
                line(path, 7, 15.5f, 17, 15.5f);
                break;
            case REFRESH:
                path.addArc(4, 4, 20, 20, -33, 290);
                line(path, 20, 4, 20, 11, 14, 11);
                break;
            case ADD:
                line(path, 12, 5, 12, 19);
                line(path, 5, 12, 19, 12);
                break;
            case BACK:
                line(path, 11, 5, 4, 12, 11, 19);
                line(path, 4, 12, 20, 12);
                break;
            case CANCEL:
                line(path, 6, 6, 18, 18);
                line(path, 18, 6, 6, 18);
                break;
            case SAVE:
                line(path, 4.5f, 12.5f, 9.5f, 17.5f, 19.5f, 6.5f);
                break;
            case MORE:
                for (int y = 6; y <= 18; y += 6) path.addCircle(12, y, 1.5f, cw);
                return path;
        }
        Paint stroke = new Paint();
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeWidth(1.85f);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeJoin(Paint.Join.ROUND);
        Path glyph = new Path();
        stroke.getFillPath(path, glyph);
        return glyph;
    }

    private static void line(Path path, float... xy) {
        path.moveTo(xy[0], xy[1]);
        for (int i = 2; i < xy.length; i += 2) path.lineTo(xy[i], xy[i + 1]);
    }

    @Override public void setAlpha(int value) {
        if (alpha == value) return;
        alpha = value;
        updatePaints();
        invalidateSelf();
    }
    @Override public void setColorFilter(ColorFilter filter) { foreground.setColorFilter(filter); invalidateSelf(); }
    @Override public int getIntrinsicWidth() { return (int)VIEWPORT; }
    @Override public int getIntrinsicHeight() { return (int)VIEWPORT; }
    @Override public ConstantState getConstantState() { return state; }
    @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
}
