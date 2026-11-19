package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class ScreenshotShelfGateTest {
 @Test public void onlyNewPublishedOwnedScreenshotsAreAccepted(){
  ScreenshotShelfGate gate=new ScreenshotShelfGate(100000);
  assertFalse(gate.accept(1,99999,"Pictures/Screenshots/","com.android.systemui",false,110000));
  assertFalse(gate.accept(2,105000,"Pictures/Screenshots/","com.android.systemui",true,110000));
  assertFalse(gate.accept(3,105000,"Pictures/Camera/","com.android.systemui",false,110000));
  assertFalse(gate.accept(4,105000,"Pictures/Screenshots/","com.example.app",false,110000));
  assertTrue(gate.accept(2,105000,"Pictures/Screenshots/","com.android.systemui",false,110000));
  assertFalse(gate.accept(2,105000,"Pictures/Screenshots/","com.android.systemui",false,110500));
 }
 @Test public void oldOrFutureRowsAreNotBackfilled(){
  ScreenshotShelfGate gate=new ScreenshotShelfGate(100000);
  assertFalse(gate.accept(1,105000,"Pictures/Screenshots/","com.android.systemui",false,200000));
  assertFalse(gate.accept(2,205000,"Pictures/Screenshots/","com.android.systemui",false,200000));
 }
 @Test public void newerExplicitCopiesArePreserved(){
  assertTrue(ScreenshotShelfGate.mayReplaceClipboard(200000,100000));
  assertFalse(ScreenshotShelfGate.mayReplaceClipboard(200000,200001));
 }
}
