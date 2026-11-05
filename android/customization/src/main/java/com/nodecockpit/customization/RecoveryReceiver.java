package com.nodecockpit.customization;
import android.content.*;
/** Only holders of platform DUMP permission may request this fail-closed operation. */
public final class RecoveryReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String action=intent.getAction();
        if (FeaturePolicy.ACTION_DISABLE.equals(action)) {
            LocalCustomization.emergency(context,"Recovery backend detected repeated SystemUI restarts");
        } else if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action)) {
            BootRecoveryJobService.schedule(context);
        }
    }
}
