package com.example.remote_control;
import org.junit.Test;
import static org.junit.Assert.*;
public class ScreenOffExitPolicyTest {
 @Test public void neverExitsBeforeScreenOff(){var p=new ScreenOffExitPolicy();assertEquals(-1,p.remaining(90000));assertFalse(p.shouldExit(90000,false,false));}
 @Test public void exitsOnlyAtThirtySeconds(){var p=new ScreenOffExitPolicy();p.screenOff(100);assertFalse(p.shouldExit(30099,false,false));assertTrue(p.shouldExit(30100,false,false));}
 @Test public void workEndingUsesOriginalDeadline(){var p=new ScreenOffExitPolicy();p.screenOff(10);assertFalse(p.shouldExit(60000,false,true));assertTrue(p.shouldExit(60000,false,false));}
 @Test public void wakeCancelsExpiredTimer(){var p=new ScreenOffExitPolicy();p.screenOff(10);p.screenOn();assertFalse(p.shouldExit(90000,false,false));}
 @Test public void staleAlarmCannotKillNewSleepSession(){var p=new ScreenOffExitPolicy();p.screenOff(0);p.screenOn();p.screenOff(29000);assertFalse(p.shouldExit(30000,false,false));assertTrue(p.shouldExit(59000,false,false));}
 @Test public void duplicateOffDoesNotExtendDeadlineAndInteractiveAlwaysWins(){var p=new ScreenOffExitPolicy();p.screenOff(0);p.screenOff(20000);assertTrue(p.shouldExit(30000,false,false));assertFalse(p.shouldExit(30000,true,false));}
}
