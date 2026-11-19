package com.nodecockpit.customization;
public final class CustomizationApplication extends android.app.Application {
    @Override public void onCreate() {
        super.onCreate();
        String process="";
        if(android.os.Build.VERSION.SDK_INT>=28)process=android.app.Application.getProcessName();
        else try{for(android.app.ActivityManager.RunningAppProcessInfo p:((android.app.ActivityManager)getSystemService(ACTIVITY_SERVICE)).getRunningAppProcesses())if(p.pid==android.os.Process.myPid()){process=p.processName;break;}}catch(Exception ignored){}
        // The optional battery observer is independent of Flutter, remote tools,
        // Xposed management and root-safety refresh work in the main process.
        if(process.endsWith(":battery")||process.endsWith(":clipboard"))return;
        LocalCustomization.initialize(this);
    }
}
