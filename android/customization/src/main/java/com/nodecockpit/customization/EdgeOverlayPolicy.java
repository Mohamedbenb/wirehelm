package com.nodecockpit.customization;
/** Pure safety/visibility policy: no trusted-overlay flags, input-filter changes or app input monitoring. */
final class EdgeOverlayPolicy {
 private boolean barKnown,barSensitive,taskKnown,taskSensitive;private String permissionPackage="";
 void permissionPackage(String value){permissionPackage=value==null?"":value;}
 boolean sensitive(String pkg,String component){String p=pkg==null?"":pkg.toLowerCase(java.util.Locale.ROOT),c=component==null?"":component.toLowerCase(java.util.Locale.ROOT);
  return !p.isEmpty()&&(p.equals(permissionPackage)||p.equals("com.android.permissioncontroller")||p.equals("com.google.android.permissioncontroller")||p.equals("com.android.packageinstaller")||p.equals("com.google.android.packageinstaller")||p.equals("com.android.settings"))
   ||c.contains("grantpermissions")||c.contains("reviewpermissions")||c.contains("confirmdevicecredential")||c.contains("biometricprompt");
 }
 void reset(){barKnown=barSensitive=taskKnown=taskSensitive=false;}
 void bar(String pkg){if(pkg==null||pkg.isEmpty())return;barKnown=true;barSensitive=sensitive(pkg,"");}
 void task(String pkg,String component){if(pkg==null||pkg.isEmpty())return;boolean wasSensitive=taskKnown&&taskSensitive;taskKnown=true;taskSensitive=sensitive(pkg,component);if(wasSensitive&&!taskSensitive){barKnown=false;barSensitive=false;}}
 boolean blocked(){return !barKnown&&!taskKnown||barSensitive||taskSensitive;}
 String reason(){return barSensitive||taskSensitive?"sensitive screen":!barKnown&&!taskKnown?"awaiting foreground":"clear";}
 static boolean needsModal(boolean exists,float target){return exists||target>0;}
}
