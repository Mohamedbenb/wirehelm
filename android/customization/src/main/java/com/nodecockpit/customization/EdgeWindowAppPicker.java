package com.nodecockpit.customization;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Executor;
import java.util.function.Consumer;

/** Search installed launcher apps and pick one without changing the edge shortcuts. */
final class EdgeWindowAppPicker extends LinearLayout {
    private static final int INK = 0xFF10161D;
    private final PackageManager packages;
    private final EditText search;
    private final TextView status;
    private final AppAdapter adapter = new AppAdapter();
    private List<App> apps;

    EdgeWindowAppPicker(Context context, Consumer<String> launch, Runnable close) {
        super(context);
        packages = context.getPackageManager();
        setOrientation(VERTICAL);
        setPadding(dp(16), dp(10), dp(16), dp(12));
        setFocusableInTouchMode(true);

        LinearLayout header = new LinearLayout(context);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = new TextView(context);
        title.setText("Add window");
        title.setTextSize(20);
        title.setTextColor(INK);
        header.addView(title, new LayoutParams(0, -2, 1));
        Button cancel = new Button(context);
        cancel.setText("Cancel");
        cancel.setOnClickListener(v -> close.run());
        header.addView(cancel);
        addView(header, new LayoutParams(-1, -2));

        search = new EditText(context);
        search.setHint("Find an app");
        search.setContentDescription("Find an app");
        search.setSingleLine(true);
        search.setTextColor(INK);
        search.setHintTextColor(0xFF526075);
        addView(search, new LayoutParams(-1, dp(52)));

        status = new TextView(context);
        status.setTextColor(INK);
        status.setGravity(Gravity.CENTER);
        status.setText("Loading apps…");
        addView(status, new LayoutParams(-1, dp(48)));
        ListView list = new ListView(context);
        list.setAdapter(adapter);
        list.setEmptyView(status);
        list.setOnItemClickListener((parent, view, position, id) -> launch.accept(adapter.getItem(position).pkg));
        addView(list, new LayoutParams(-1, 0, 1));

        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { filter(); }
            @Override public void afterTextChanged(Editable text) {}
        });
    }

    void load(Executor worker) {
        worker.execute(() -> {
            List<App> loaded = new ArrayList<>();
            try {
                Intent launcher = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
                HashSet<String> seen = new HashSet<>();
                for (ResolveInfo match : packages.queryIntentActivities(launcher, 0)) {
                    if (match.activityInfo == null || !match.activityInfo.exported) continue;
                    String pkg = match.activityInfo.packageName;
                    if (seen.add(pkg)) loaded.add(new App(pkg, match.loadLabel(packages).toString(), match));
                }
                loaded.sort((a, b) -> String.CASE_INSENSITIVE_ORDER.compare(a.label, b.label));
            } catch (RuntimeException error) {
                post(() -> status.setText("Could not load apps"));
                return;
            }
            post(() -> {
                if (!isAttachedToWindow()) return;
                apps = loaded;
                filter();
            });
        });
    }

    private void filter() {
        if (apps == null) return;
        String query = search.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<App> matches = new ArrayList<>();
        for (App app : apps) {
            if (app.label.toLowerCase(Locale.ROOT).contains(query) || app.pkg.contains(query)) matches.add(app);
        }
        status.setText("No apps found");
        adapter.matches = matches;
        adapter.notifyDataSetChanged();
    }

    private final class AppAdapter extends BaseAdapter {
        List<App> matches = Collections.emptyList();

        @Override public int getCount() { return matches.size(); }
        @Override public App getItem(int position) { return matches.get(position); }
        @Override public long getItemId(int position) { return position; }

        @Override public View getView(int position, View recycled, ViewGroup parent) {
            LinearLayout row = (LinearLayout) recycled;
            if (row == null) {
                row = new LinearLayout(getContext());
                row.setGravity(Gravity.CENTER_VERTICAL);
                row.setMinimumHeight(dp(54));
                row.addView(new ImageView(getContext()), new LayoutParams(dp(36), dp(36)));
                TextView text = new TextView(getContext());
                text.setTextColor(INK);
                text.setTextSize(15);
                text.setMaxLines(2);
                text.setEllipsize(TextUtils.TruncateAt.END);
                text.setPadding(dp(12), 0, 0, 0);
                row.addView(text, new LayoutParams(0, -2, 1));
            }
            App app = getItem(position);
            ImageView icon = (ImageView) row.getChildAt(0);
            icon.setImageDrawable(app.info.loadIcon(packages));
            EdgePanelInk.icon(icon, INK);
            TextView label = (TextView) row.getChildAt(1);
            label.setText(app.label);
            EdgePanelInk.text(label, INK);
            return row;
        }
    }

    private static final class App {
        final String pkg;
        final String label;
        final ResolveInfo info;

        App(String pkg, String label, ResolveInfo info) {
            this.pkg = pkg;
            this.label = label;
            this.info = info;
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
