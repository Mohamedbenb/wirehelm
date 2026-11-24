package com.nodecockpit.customization;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/** The draft stays local until Send text or a key button is tapped. */
final class EdgeKeyboardControls implements EdgeControlPage {
    private final Context context;
    private final EdgeControlRequest connection;
    private final LinearLayout pane, input;
    private final TextView status;
    private final EditText draft;
    private final GradientDrawable draftBackground = new GradientDrawable();
    private final List<TextView> buttons = new ArrayList<>();
    private boolean busy;

    EdgeKeyboardControls(Context context, Handler main, boolean configured) {
        this.context = context;
        connection = configured ? new EdgeControlRequest(context, main, true) : null;
        pane = column();
        status = new TextView(context);
        status.setTextSize(12);
        status.setMinHeight(dp(30));
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        pane.addView(status, new LinearLayout.LayoutParams(-1, -2));

        input = column();
        pane.addView(input, new LinearLayout.LayoutParams(-1, -2));
        draft = new EditText(context);
        draft.setHint("Type text");
        draftBackground.setCornerRadius(dp(10));
        draft.setBackground(draftBackground);
        draft.setPaddingRelative(dp(8), dp(8), dp(8), dp(8));
        setDraftInk(0xff16181d);
        draft.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
            | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        draft.setImeOptions(EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        draft.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        draft.setSaveEnabled(false);
        draft.setMinHeight(dp(52));
        draft.setMaxLines(4);
        draft.setTextSize(14);
        draft.setFilters(new InputFilter[]{new InputFilter.LengthFilter(4096)});
        input.addView(draft, new LinearLayout.LayoutParams(-1, -2));
        addButton(input, "Send text", () -> {
            String text = draft.getText().toString();
            if (text.isEmpty()) return;
            if (text.indexOf(0) >= 0) {
                status.setText("Remove null characters before sending.");
                return;
            }
            Bundle args = new Bundle();
            args.putString("text", text);
            send(args, text);
        }, new LinearLayout.LayoutParams(-1, -2));

        addKeys("Enter", "Tab");
        addKeys("Escape", "Backspace");
        addKeys("Left", "Right");
        addKeys("Up", "Down");
        addKeys("Copy", "Paste");
        input.setVisibility(View.GONE);
        if (configured) refresh();
        else status.setText("Choose a keyboard host in Panel actions.");
    }

    @Override public LinearLayout view() { return pane; }

    @Override public void refresh() {
        if (connection == null || busy) return;
        setBusy(true);
        status.setText("Connecting…");
        connection.call("keyboardRead", new Bundle(), result -> receive(result, null, false));
    }

    @Override public void setInk(int ink) {
        EdgePanelInk.text(status, ink);
        setDraftInk(ink);
        for (TextView button : buttons) EdgePanelInk.text(button, ink);
    }

    private void setDraftInk(int panelInk) {
        boolean light = Color.luminance(panelInk) > .179f;
        int text = light ? 0xfff7f7fa : 0xff16181d;
        if (draft.getCurrentTextColor() == text && draftBackground.getColor() != null) return;
        draft.setTextColor(text);
        draft.setHintTextColor(light ? 0xffdedee5 : 0xff43454f);
        draftBackground.setColor(light ? 0xef202126 : 0xefffffff);
        draftBackground.setStroke(dp(1), light ? 0x557f8591 : 0x5543454f);
    }

    @Override public void close() {
        if (connection != null) connection.close();
        draft.getText().clear();
    }

    private void addKeys(String first, String second) {
        LinearLayout keys = new LinearLayout(context);
        for (String key : new String[]{first, second}) {
            addButton(keys, key, () -> {
                Bundle args = new Bundle();
                args.putString("key", key);
                send(args, null);
            }, new LinearLayout.LayoutParams(0, -2, 1));
        }
        input.addView(keys, new LinearLayout.LayoutParams(-1, -2));
    }

    private void addButton(LinearLayout parent, String label, Runnable click, LinearLayout.LayoutParams bounds) {
        TextView button = new TextView(context);
        button.setText(label);
        button.setTextSize(12);
        button.setGravity(Gravity.CENTER);
        button.setMinHeight(dp(48));
        button.setFocusable(true);
        android.util.TypedValue background = new android.util.TypedValue();
        if (context.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, background, true))
            button.setBackgroundResource(background.resourceId);
        button.setOnClickListener(v -> click.run());
        buttons.add(button);
        parent.addView(button, bounds);
    }

    private void send(Bundle args, String sentText) {
        if (connection == null || busy) return;
        setBusy(true);
        status.setText("Sending… Approve KDE access on the PC if prompted.");
        connection.call("keyboardSend", args, result -> receive(result, sentText, true));
    }

    private void receive(Bundle result, String sentText, boolean sending) {
        setBusy(false);
        String error = result.getString("error");
        boolean ready = result.getBoolean("ready");
        if (error != null || !ready) {
            if (sending) status.setText("Input was not confirmed. Check keyboard access in Wirehelm.");
            else status.setText(error != null ? error : "Keyboard host is unavailable.");
            return;
        }
        if (sentText != null && sentText.contentEquals(draft.getText())) draft.getText().clear();
        input.setVisibility(View.VISIBLE);
        status.setText(result.getString("deviceName", "Desktop") + (sending ? " · Sent" : ""));
    }

    private void setBusy(boolean active) {
        busy = active;
        for (TextView button : buttons) {
            button.setEnabled(!active);
            button.setAlpha(active ? 0.6f : 1f);
        }
    }

    private LinearLayout column() {
        LinearLayout view = new LinearLayout(context);
        view.setOrientation(LinearLayout.VERTICAL);
        return view;
    }

    private int dp(int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
