package com.nodecockpit.customization;

import android.widget.LinearLayout;

interface EdgeControlPage {
    LinearLayout view();
    void refresh();
    void setInk(int ink);
    void close();
}
