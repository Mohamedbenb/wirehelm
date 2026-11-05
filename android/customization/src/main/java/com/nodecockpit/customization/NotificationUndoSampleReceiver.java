package com.nodecockpit.customization;
import android.content.*;
public final class NotificationUndoSampleReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context,Intent intent){try{NotificationUndoSamples.receive(context,intent);}catch(RuntimeException e){android.util.Log.w("NodeUndoSample","Sample callback unavailable",e);}}
}
