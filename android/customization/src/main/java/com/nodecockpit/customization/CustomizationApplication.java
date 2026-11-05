package com.nodecockpit.customization;
public final class CustomizationApplication extends android.app.Application {
    @Override public void onCreate() { super.onCreate(); LocalCustomization.initialize(this); }
}
