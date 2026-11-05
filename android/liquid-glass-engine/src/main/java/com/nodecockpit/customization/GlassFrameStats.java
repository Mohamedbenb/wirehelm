package com.nodecockpit.customization;
/** Only distinct valid Android present timestamps count; invalid fence times are not FPS. */
final class GlassFrameStats {
 long lastPresent,gpuSum;int presented,gpuCount,reports,dropped,missed;
 void frame(long present,long gpu,long total,long deadline,int drops){reports++;dropped+=Math.max(0,drops);if(validTime(present)&&present>lastPresent){lastPresent=present;presented++;}if(gpu>=0&&gpu<1000000000L){gpuSum+=gpu;gpuCount++;}if(total>0&&deadline>0&&total>deadline)missed++;}
 static boolean validTime(long time){return time>0&&time<Long.MAX_VALUE/2;}
 String windowSnapshot(){String gpu=gpuCount==0?"pending":String.format(java.util.Locale.ROOT,"%.2fms",gpuSum/1000000.0/gpuCount);String result=String.format(java.util.Locale.ROOT,"Host frame reports: %d (not presentation FPS)\nHWUI GPU: %s | late: %d/%d | lost reports: %d",reports,gpu,missed,reports,dropped);presented=gpuCount=reports=dropped=missed=0;gpuSum=0;return result;}
 String snapshot(double seconds){String gpu=gpuCount==0?"pending":String.format(java.util.Locale.ROOT,"%.2fms",gpuSum/1000000.0/gpuCount);String result=String.format(java.util.Locale.ROOT,"Presented FPS: %.0f (host)\nHWUI GPU: %s | late: %d/%d | lost: %d",presented/Math.max(.001,seconds),gpu,missed,reports,dropped);presented=gpuCount=reports=dropped=missed=0;gpuSum=0;return result;}
}
