package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public final class SavedSetupScopeTest {
 @Test public void networkSaveLeavesOtherFeaturesAndSafetyUntouched() {
  for(String key:new String[]{"indicatorDesign","horizontalPosition","enabled","unitGap","intervalMs"}) assertTrue(SavedSetupScope.owns("network",key));
  for(String key:new String[]{"edgePanelApps","edgeHandleBlur","shadeGlassEnabled","systemGlassStyle","revision","emergencyDisabled","recoveryReason","safetyAt"}) assertFalse(SavedSetupScope.owns("network",key));
 }
 @Test public void edgeAndGlassHaveIndependentOwnership() {
  assertTrue(SavedSetupScope.owns("edge","edgeHandleTintMode")); assertTrue(SavedSetupScope.owns("edge","edgePanelFolderNames"));
  assertFalse(SavedSetupScope.owns("edge","systemGlassStyle")); assertFalse(SavedSetupScope.owns("edge","enabled"));
  assertTrue(SavedSetupScope.owns("glass","systemGlassStyle")); assertTrue(SavedSetupScope.owns("glass","lockGlassEnabled"));
  assertFalse(SavedSetupScope.owns("glass","edgePanelOpacity"));
 }
 @Test public void fullSaveStillExcludesRuntimeSafety() { assertTrue(SavedSetupScope.owns("all","unitSuffix")); assertFalse(SavedSetupScope.owns("all","safetyBoot")); }
 @Test(expected=IllegalArgumentException.class) public void unknownScopeCannotOverwriteSetup() { SavedSetupScope.owns("unknown","enabled"); }
}
