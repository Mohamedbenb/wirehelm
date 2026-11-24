package com.nodecockpit.customization;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

final class EdgeControlList {
    enum Entry {
        BULB("bulb", "Smart bulb", EdgePanelIcon.Kind.BULB),
        POWER("power", "PC power", EdgePanelIcon.Kind.POWER),
        TEXT("text", "PC text size", EdgePanelIcon.Kind.TEXT),
        KEYBOARD("keyboard", "Remote keyboard", EdgePanelIcon.Kind.KEYBOARD);

        final String id;
        final String label;
        final EdgePanelIcon.Kind icon;

        Entry(String id, String label, EdgePanelIcon.Kind icon) {
            this.id = id;
            this.label = label;
            this.icon = icon;
        }
    }

    final LinearLayout view;
    private final List<TextView> labels = new ArrayList<>();
    private final List<ImageView> icons = new ArrayList<>();
    private final List<RippleDrawable> ripples = new ArrayList<>();
    private Integer foreground, iconForeground;

    EdgeControlList(Context context, List<String> controls, Consumer<Entry> open) {
        view = new LinearLayout(context);
        view.setOrientation(LinearLayout.VERTICAL);
        float density = context.getResources().getDisplayMetrics().density;
        int iconSize = Math.round(22 * density);
        int gap = Math.round(8 * density);

        if (controls.isEmpty()) {
            TextView label = new TextView(context);
            label.setText("Choose controls in Panel actions.");
            label.setTextSize(13);
            labels.add(label);
            view.addView(label);
        }
        for (String id : controls) for (Entry entry : Entry.values()) {
            if (!entry.id.equals(id)) continue;
            LinearLayout row = new LinearLayout(context);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setMinimumHeight(Math.round(48 * density));
            row.setFocusable(true);
            GradientDrawable mask = new GradientDrawable();
            mask.setColor(Color.WHITE);
            mask.setCornerRadius(Math.round(12 * density));
            RippleDrawable ripple = new RippleDrawable(ColorStateList.valueOf(0x28ffffff), null, mask);
            row.setBackground(ripple);
            ripples.add(ripple);

            ImageView icon = new ImageView(context);
            icon.setImageDrawable(new EdgePanelIcon(entry.icon));
            icon.setImportantForAccessibility(ImageView.IMPORTANT_FOR_ACCESSIBILITY_NO);
            LinearLayout.LayoutParams iconLayout = new LinearLayout.LayoutParams(iconSize, iconSize);
            iconLayout.setMarginEnd(gap);
            row.addView(icon, iconLayout);
            icons.add(icon);

            TextView label = new TextView(context);
            label.setText(entry.label);
            label.setTextSize(13);
            label.setImportantForAccessibility(TextView.IMPORTANT_FOR_ACCESSIBILITY_NO);
            row.addView(label, new LinearLayout.LayoutParams(0, -2, 1));
            labels.add(label);
            row.setContentDescription(entry.label);
            row.setOnClickListener(v -> open.accept(entry));
            view.addView(row, new LinearLayout.LayoutParams(-1, -2));
        }
    }

    void setInk(int ink, int iconInk) {
        if (foreground != null && foreground == ink && iconForeground == iconInk) return;
        foreground = ink;
        iconForeground = iconInk;
        for (TextView label : labels) EdgePanelInk.text(label, ink);
        for (ImageView icon : icons) EdgePanelInk.icon(icon, iconInk);
        ColorStateList ripple = ColorStateList.valueOf((ink & 0x00ffffff) | 0x28000000);
        for (RippleDrawable background : ripples) background.setColor(ripple);
    }
}
