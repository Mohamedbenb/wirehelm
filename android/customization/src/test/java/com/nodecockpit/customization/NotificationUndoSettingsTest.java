package com.nodecockpit.customization;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;
public class NotificationUndoSettingsTest {
    @Test public void savedChoicesSurviveNewRuntimeSnapshot()throws Exception{String raw="{\"enabled\":true,\"shake\":false,\"sensitivity\":2}";NotificationUndoSettings before=new NotificationUndoSettings(raw),after=new NotificationUndoSettings(new JSONObject(raw).toString());assertTrue(before.enabled&&after.enabled);assertFalse(after.shake);assertEquals(2,after.sensitivity);}
    @Test public void freshInstallIsOptInButExistingTestersMigrateEnabled(){assertFalse(NotificationUndoSettings.safe(NotificationUndoSettings.DEFAULT).enabled);assertTrue(NotificationUndoSettings.safe(NotificationUndoSettings.MIGRATED).enabled);}
    @Test public void malformedSettingsFailClosed(){assertFalse(NotificationUndoSettings.safe("broken").enabled);assertFalse(NotificationUndoSettings.safe("{\"enabled\":\"true\"}").enabled);}
    @Test public void invalidStrengthRejected()throws Exception{for(String value:new String[]{"-1","3","1.5","\"1\""})try{new NotificationUndoSettings("{\"sensitivity\":"+value+"}");fail(value);}catch(IllegalArgumentException expected){}}
    @Test public void safetyDisablePreservesGestureChoices()throws Exception{NotificationUndoSettings s=new NotificationUndoSettings(NotificationUndoSettings.disabled("{\"enabled\":true,\"shake\":false,\"sensitivity\":2}"));assertFalse(s.enabled);assertFalse(s.shake);assertEquals(2,s.sensitivity);}
    @Test public void staleOtherFeatureCannotDisableUndo()throws Exception{JSONObject stale=new JSONObject().put("notificationUndo",NotificationUndoSettings.DEFAULT);NotificationUndoSettings.mergeOwnership(stale,NotificationUndoSettings.MIGRATED,false);assertTrue(new NotificationUndoSettings(stale.getString("notificationUndo")).enabled);}
    @Test public void FeatureOwnerCanDisableUndo()throws Exception{JSONObject own=new JSONObject().put("notificationUndo",NotificationUndoSettings.DEFAULT);NotificationUndoSettings.mergeOwnership(own,NotificationUndoSettings.MIGRATED,true);assertFalse(new NotificationUndoSettings(own.getString("notificationUndo")).enabled);}
    @Test public void oversizedSettingsRejected()throws Exception{try{new NotificationUndoSettings(" ".repeat(513));fail();}catch(IllegalArgumentException expected){}}
    @Test public void buttonCanBeDisabledWhileShakeRemainsAvailable()throws Exception{NotificationUndoSettings s=new NotificationUndoSettings("{\"enabled\":true,\"button\":false,\"shake\":true}");assertTrue(s.enabled&&s.shake);assertFalse(s.button);}
    @Test public void enabledFeatureRequiresAnUndoMethod()throws Exception{try{new NotificationUndoSettings("{\"enabled\":true,\"button\":false,\"shake\":false}");fail();}catch(IllegalArgumentException expected){}}
    @Test public void oldSavedSettingsKeepButtonAvailable()throws Exception{assertTrue(new NotificationUndoSettings("{\"enabled\":true,\"shake\":false}").button);}
}
