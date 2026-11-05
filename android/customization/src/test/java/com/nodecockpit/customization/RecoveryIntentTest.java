package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public final class RecoveryIntentTest {
    @Test public void automaticFaultsRetainAllDesiredFeatureChoices() {
        for (String reason:new String[]{"Hook disabled itself: timeout","Recovery backend accessDenied; customization stopped","SystemUI restart protection quarantined customization","Apply failed: Root request timed out",null,""})
            assertFalse(FeaturePolicy.clearDesiredOnEmergency(reason));
    }
    @Test public void explicitDisableClearsDesiredFeatureChoices() {
        assertTrue(FeaturePolicy.clearDesiredOnEmergency("Disabled by user"));
    }
}
