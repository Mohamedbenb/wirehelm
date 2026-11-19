package com.nodecockpit.customization;

import android.app.KeyguardManager;
import android.content.*;
import android.net.Uri;
import android.database.ContentObserver;
import android.provider.MediaStore;
import android.os.*;
import java.util.concurrent.*;

/** Event-only capture inside privileged SystemUI; never changes the stock clipboard overlay. */
final class ClipboardShelfObserver {
    private final Context context;
    private final ClipboardManager clipboard;
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,
        new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"Wirehelm-clipboard");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardPolicy());
    private final Uri target=Uri.parse("content://com.example.remote_control.clipboard.shelf");
    private final java.util.concurrent.atomic.AtomicBoolean clipPending=new java.util.concurrent.atomic.AtomicBoolean();
    private final java.util.concurrent.atomic.AtomicBoolean imagePending=new java.util.concurrent.atomic.AtomicBoolean();
    private final java.util.concurrent.atomic.AtomicBoolean scheduled=new java.util.concurrent.atomic.AtomicBoolean();
    private final ScreenshotShelfGate screenshots=new ScreenshotShelfGate(System.currentTimeMillis());
    private final long imageStart=System.currentTimeMillis();
    private final ClipboardManager.OnPrimaryClipChangedListener listener=()->request(false);
    private final ContentObserver images=new ContentObserver(new Handler(Looper.getMainLooper())){
        @Override public void onChange(boolean selfChange){request(true);}
    };
    ClipboardShelfObserver(Context c){
        context=c;clipboard=c.getSystemService(ClipboardManager.class);
        clipboard.addPrimaryClipChangedListener(listener);
        context.getContentResolver().registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,true,images);
        context.getContentResolver().registerContentObserver(MediaStore.Images.Media.getContentUri("external_primary"),true,images);
        worker.execute(()->{try{policy();}catch(Throwable ignored){}});
    }
    private Bundle policy(){
        Bundle b=new Bundle();b.putInt("version",FeaturePolicy.HOOK_VERSION);
        b.putInt("boot",android.provider.Settings.Global.getInt(context.getContentResolver(),android.provider.Settings.Global.BOOT_COUNT,-1));
        return context.getContentResolver().call(target,"policy",null,b);
    }
    private void request(boolean image){
        (image?imagePending:clipPending).set(true);schedule();
    }
    private void schedule(){
        if(!scheduled.compareAndSet(false,true))return;
        worker.execute(()->{
            try{for(int i=0;i<4;i++){
                if(clipPending.getAndSet(false))capture();
                if(imagePending.getAndSet(false))screenshots();
                if(!clipPending.get()&&!imagePending.get())break;
            }}finally{scheduled.set(false);if(clipPending.get()||imagePending.get())schedule();}
        });
    }
    private boolean unlocked() throws Exception{
        int current=(Integer)Class.forName("android.app.ActivityManager").getMethod("getCurrentUser").invoke(null);
        return current==android.os.Process.myUid()/100000&&context.getSystemService(UserManager.class).isUserUnlocked()&&!context.getSystemService(KeyguardManager.class).isDeviceLocked();
    }
    private void screenshots(){
        try{
            String[] columns={"_id","datetaken","relative_path","owner_package_name","is_pending"};
            Bundle args=new Bundle();args.putString(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION,"date_added>=? AND owner_package_name=? AND relative_path LIKE ?");
            args.putStringArray(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,new String[]{String.valueOf(Math.max(imageStart/1000,System.currentTimeMillis()/1000-60)),"com.android.systemui","%Screenshots/%"});
            args.putString(android.content.ContentResolver.QUERY_ARG_SQL_SORT_ORDER,"_id DESC");args.putInt(android.content.ContentResolver.QUERY_ARG_LIMIT,8);
            try(android.database.Cursor cursor=context.getContentResolver().query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,columns,args,null)){
                if(cursor==null)return;
                for(int position=Math.min(cursor.getCount(),8)-1;position>=0;position--){
                    cursor.moveToPosition(position);
                    long id=cursor.getLong(0),taken=cursor.getLong(1);
                    if(!screenshots.accept(id,taken,cursor.getString(2),cursor.getString(3),cursor.getInt(4)!=0,System.currentTimeMillis()))continue;
                    if(!unlocked())continue;
                    Bundle p=policy();if(p==null||!p.getBoolean("enabled")||!p.getBoolean("screenshots"))continue;
                    java.util.ArrayList<String> excluded=p.getStringArrayList("excluded");if(excluded!=null&&excluded.contains("com.android.systemui"))continue;
                    Uri uri=ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,id);
                    try(ParcelFileDescriptor fd=context.getContentResolver().openFileDescriptor(uri,"r")){
                        if(fd==null||fd.getStatSize()<=0||fd.getStatSize()>8*1024*1024)continue;
                        Bundle data=new Bundle();data.putString("source","com.android.systemui");data.putBoolean("sensitive",false);data.putBoolean("screenshot",true);data.putParcelable("image",fd);
                        Bundle result=context.getContentResolver().call(target,"capture",null,data);
                        ClipDescription current=clipboard.getPrimaryClipDescription();
                        Bundle latest=policy();
                        if(result!=null&&result.getBoolean("stored")&&unlocked()&&latest!=null&&latest.getBoolean("enabled")&&latest.getBoolean("screenshots")&&ScreenshotShelfGate.mayReplaceClipboard(taken,current==null?0:current.getTimestamp()))
                            clipboard.setPrimaryClip(ClipData.newUri(context.getContentResolver(),"Screenshot",uri));
                    }
                }
            }
        }catch(Throwable ignored){ /* Unsupported publication must never affect screenshot saving. */ }
    }
    private void capture(){
        try{
            // Never cross user/profile boundaries or retain locked-screen copies.
            if(!unlocked())return;
            Bundle p=policy();if(p==null||!p.getBoolean("enabled"))return;
            String source=(String)ClipboardManager.class.getMethod("getPrimaryClipSource").invoke(clipboard);
            if(source==null||source.isEmpty()||source.equals("com.example.remote_control"))return;
            java.util.ArrayList<String> excluded=p.getStringArrayList("excluded");if(excluded!=null&&excluded.contains(source))return;
            ClipDescription description=clipboard.getPrimaryClipDescription();
            if(description==null||description.getExtras()!=null&&description.getExtras().getBoolean("android.content.extra.IS_SENSITIVE",false))return;
            ClipData clip=clipboard.getPrimaryClip();if(clip==null||clip.getItemCount()==0)return;
            if(clip.getDescription().getExtras()!=null&&clip.getDescription().getExtras().getBoolean("android.content.extra.IS_SENSITIVE",false))return;
            if(!source.equals(ClipboardManager.class.getMethod("getPrimaryClipSource").invoke(clipboard)))return;
            Bundle data=new Bundle();data.putString("source",source);data.putBoolean("sensitive",false);
            ClipData.Item item=clip.getItemAt(0);CharSequence text=item.getText();
            if(text!=null){if(text.length()>65536)return;data.putString("text",text.toString());context.getContentResolver().call(target,"capture",null,data);}
            else if(p.getBoolean("images")&&item.getUri()!=null&&"content".equals(item.getUri().getScheme())&&clip.getDescription().hasMimeType("image/*")){
                try(ParcelFileDescriptor fd=context.getContentResolver().openFileDescriptor(item.getUri(),"r")){
                    if(fd==null||fd.getStatSize()<=0||fd.getStatSize()>8*1024*1024)return;
                    data.putParcelable("image",fd);context.getContentResolver().call(target,"capture",null,data);
                }
            }
        }catch(Throwable ignored){ /* Never log clipboard contents, block SystemUI or affect stock copy. */ }
    }
}
