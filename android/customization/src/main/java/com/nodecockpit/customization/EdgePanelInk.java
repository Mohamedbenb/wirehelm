package com.nodecockpit.customization;

import android.graphics.Color;
import android.graphics.drawable.AdaptiveIconDrawable;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.TextView;

/** Applies the panel’s text and icon contrast treatment. */
final class EdgePanelInk {
    private EdgePanelInk() {}

    static void text(TextView label, int ink) {
        text(label, ink, Color.TRANSPARENT);
    }

    static void text(TextView label, int ink, int fill) {
        backing(label, 5, fill);
        if (label.getCurrentTextColor() != ink) label.setTextColor(ink);
        if (label instanceof EditText && label.getCurrentHintTextColor() != ink) label.setHintTextColor(ink);
        int shadow = Color.luminance(ink) > .179f ? 0x99000000 : 0x99ffffff;
        float px = Math.round(label.getResources().getDisplayMetrics().density);
        if (label.getShadowColor() != shadow || label.getShadowRadius() != px)
            label.setShadowLayer(px, 0, px, shadow);
    }

    static void icon(ImageView image, int ink) {
        if (image.getDrawable() instanceof EdgePanelIcon glyph) {
            glyph.setInk(ink);
        }
        if (image.getDrawable() instanceof AdaptiveIconDrawable) {
            backing(image, 6, Color.TRANSPARENT);
        }
    }

    static void dialog(View view, int ink) {
        if (view instanceof TextView label) text(label, label.getCurrentTextColor());
        if (view instanceof ImageView image) icon(image, ink);
        if (view instanceof ViewGroup group)
            for (int i = 0; i < group.getChildCount(); i++) dialog(group.getChildAt(i), ink);
    }

    private static EdgeInkBacking backing(View view, int radius, int fill) {
        Drawable background = view.getBackground();
        EdgeInkBacking backing;
        if (background instanceof EdgeInkBacking existing) {
            backing = existing;
        } else {
            int start = view.getPaddingStart(), end = view.getPaddingEnd();
            int top = view.getPaddingTop(), bottom = view.getPaddingBottom();
            boolean relative = view.isPaddingRelative();
            int left = view.getPaddingLeft(), right = view.getPaddingRight();
            backing = new EdgeInkBacking(view, background);
            backing.setCornerRadius(radius * view.getResources().getDisplayMetrics().density);
            view.setBackground(backing);
            backing.bind();
            if (relative) view.setPaddingRelative(start, top, end, bottom);
            else view.setPadding(left, top, right, bottom);
        }
        if (backing.getColor() == null || backing.getColor().getDefaultColor() != fill)
            backing.setColor(fill);
        return backing;
    }
}
