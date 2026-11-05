package com.nodecockpit.customization;
import org.json.*;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;
public class CameraRingSelectionTest {
    private CameraRingSettings config(boolean enabled,boolean ongoing)throws Exception{
        return new CameraRingSettings("{\"enabled\":"+enabled+",\"includeOngoing\":"+ongoing+",\"apps\":[{\"package\":\"a.low\",\"priority\":1},{\"package\":\"a.high\",\"priority\":5},{\"package\":\"a.equal\",\"priority\":5}]}");
    }
    private CameraRingSelection.Notice n(String key,String pkg,long time){return new CameraRingSelection.Notice(key,pkg,time,false,false);}
    @Test public void priorityBeatsRecency()throws Exception{assertEquals("high",CameraRingSelection.winner(config(true,false),List.of(n("low","a.low",999),n("high","a.high",1))).key);}
    @Test public void equalPriorityUsesNewest()throws Exception{assertEquals("new",CameraRingSelection.winner(config(true,false),List.of(n("old","a.high",1),n("new","a.equal",2))).key);}
    @Test public void equalTimestampsHaveStableWinner()throws Exception{assertEquals("a",CameraRingSelection.winner(config(true,false),List.of(n("z","a.high",2),n("a","a.equal",2))).key);}
    @Test public void removingHighestRevealsRemaining()throws Exception{List<CameraRingSelection.Notice> all=new ArrayList<>(List.of(n("low","a.low",1),n("high","a.high",2)));assertEquals("high",CameraRingSelection.winner(config(true,false),all).key);all.remove(1);assertEquals("low",CameraRingSelection.winner(config(true,false),all).key);all.clear();assertNull(CameraRingSelection.winner(config(true,false),all));}
    @Test public void disabledAndUnselectedStayDark()throws Exception{assertNull(CameraRingSelection.winner(config(false,false),List.of(n("a","a.high",1))));assertNull(CameraRingSelection.winner(config(true,false),List.of(n("a","a.other",1))));}
    @Test public void summaryDoesNotKeepRingAlive()throws Exception{assertNull(CameraRingSelection.winner(config(true,true),List.of(new CameraRingSelection.Notice("a","a.high",1,false,true))));}
    @Test public void ongoingIsOptIn()throws Exception{List<CameraRingSelection.Notice> all=List.of(new CameraRingSelection.Notice("a","a.high",1,true,false));assertNull(CameraRingSelection.winner(config(true,false),all));assertNotNull(CameraRingSelection.winner(config(true,true),all));}
    @Test public void appearanceDefaultsAreBolderThanPrototype()throws Exception{CameraRingSettings s=new CameraRingSettings(CameraRingSettings.DEFAULT);assertEquals(3,s.thickness,0);assertEquals(100,s.intensity);assertEquals(2500,s.intervalMs);assertFalse(s.enabled);}
    @Test public void invalidNumericInputsRejected()throws Exception{for(String raw:new String[]{"{\"thickness\":0}","{\"thickness\":9}","{\"intensity\":101}","{\"intensity\":20.5}","{\"intervalMs\":100}","{\"intervalMs\":\"2500\"}","{\"enabled\":1}"}){try{new CameraRingSettings(raw);fail(raw);}catch(IllegalArgumentException expected){}}}
    @Test public void invalidRulesRejected()throws Exception{for(String rules:new String[]{"[{\"package\":\"bad\"}]","[{\"package\":\"a.good\",\"priority\":0}]","[{\"package\":\"a.good\",\"priority\":6}]","[{\"package\":\"a.good\",\"color\":\"red\"}]","[{\"package\":\"a.good\"},{\"package\":\"a.good\"}]"}){try{new CameraRingSettings("{\"apps\":"+rules+"}");fail(rules);}catch(IllegalArgumentException expected){}}}
    @Test public void ruleCountAndPayloadAreBounded()throws Exception{JSONArray a=new JSONArray();for(int i=0;i<65;i++)a.put(new JSONObject().put("package","a.app"+i));try{new CameraRingSettings(new JSONObject().put("apps",a).toString());fail();}catch(IllegalArgumentException expected){}try{new CameraRingSettings(" ".repeat(16001));fail();}catch(IllegalArgumentException expected){}}
    @Test public void safetyDisablePreservesRulesAndAppearance()throws Exception{String raw="{\"enabled\":true,\"thickness\":4,\"apps\":[{\"package\":\"a.high\",\"priority\":5,\"color\":\"#FF0000\"}]}";CameraRingSettings s=new CameraRingSettings(CameraRingSettings.disabled(raw));assertFalse(s.enabled);assertEquals(4,s.thickness,0);assertEquals(5,s.apps.get("a.high").priority);}
    @Test public void invalidPersistedSettingsFailClosed(){assertFalse(CameraRingSettings.safe("broken").enabled);}
    @Test public void testPreviewUsesHighestConfiguredAppEvenWhenDisabled()throws Exception{assertEquals("a.high",CameraRingSelection.preview(config(false,false)).pkg);}
    @Test public void testWithoutAppsHasNoSyntheticNotification()throws Exception{assertNull(CameraRingSelection.preview(new CameraRingSettings(CameraRingSettings.DEFAULT)));assertNull(CameraRingSelection.winner(config(false,false),List.of(n("a","a.high",1))));}
    @Test public void staleUnrelatedPageCannotDisableRing()throws Exception{JSONObject old=new JSONObject().put("cameraRing",CameraRingSettings.DEFAULT).put("textSize",12);String current="{\"enabled\":true,\"apps\":[{\"package\":\"a.high\",\"priority\":5}]}";CameraRingSettings.mergeOwnership(old,current,false);assertEquals(current,old.getString("cameraRing"));assertEquals(12,old.getInt("textSize"));}
    @Test public void featureSaveAndFullRestoreCanChangeRing()throws Exception{JSONObject update=new JSONObject().put("cameraRing",CameraRingSettings.DEFAULT);CameraRingSettings.mergeOwnership(update,"{\"enabled\":true}",true);assertFalse(new CameraRingSettings(update.getString("cameraRing")).enabled);JSONObject oldBackup=new JSONObject();CameraRingSettings.mergeOwnership(oldBackup,"{\"enabled\":true}",true);assertFalse(new CameraRingSettings(oldBackup.getString("cameraRing")).enabled);}
}
