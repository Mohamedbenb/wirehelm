package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class FeaturePolicyTest {
    @Test public void otaAndUnvalidatedDevicesFailClosed() {
        assertTrue(FeaturePolicy.supported(37, FeaturePolicy.TESTED_FINGERPRINT));
        assertFalse(FeaturePolicy.supported(36, FeaturePolicy.TESTED_FINGERPRINT));
        assertFalse(FeaturePolicy.supported(37, "unknown/OTA"));
    }
    @Test public void boundedConfigurationRejectsUnsafePollingAndSizes() {
        assertTrue(FeaturePolicy.valid(1000,1,10));
        assertFalse(FeaturePolicy.valid(1,1,10));
        assertFalse(FeaturePolicy.valid(1000,-1,10));
        assertFalse(FeaturePolicy.valid(1000,1,100));
        assertTrue(FeaturePolicy.validLayout(16,38,8,140,0,6,6,0));
        assertFalse(FeaturePolicy.validLayout(30,38,8,140,0,6,6,0));
        assertFalse(FeaturePolicy.validLayout(16,38,8,140,-9,6,6,0));
        assertFalse(FeaturePolicy.validLayout(16,38,8,300,0,6,6,0));
    }
    @Test public void ratesUseElapsedTimeAndHandleCounterReset() {
        assertEquals("1K",FeaturePolicy.formatRate(2048,2000));
        assertEquals("2.0M",FeaturePolicy.formatRate(2097152,1000));
        assertEquals("—",FeaturePolicy.formatRate(-1,1000));
        assertEquals("—",FeaturePolicy.formatRate(1,0));
    }
    @Test public void safetyLeaseCannotSurviveAnotherBootOrExtendPastItsDeadline() {
        assertTrue(FeaturePolicy.safetyLeaseValid(4,4,2000,1000));
        assertFalse(FeaturePolicy.safetyLeaseValid(5,4,2000,1000));
        assertFalse(FeaturePolicy.safetyLeaseValid(4,4,1000+FeaturePolicy.SAFETY_LEASE_MS,1000));
        assertFalse(FeaturePolicy.safetyLeaseValid(-1,-1,2000,1000));
        assertFalse(FeaturePolicy.safetyLeaseValid(4,4,500,1000));
    }
    @Test public void readoutSupportsZeroBitsAndRoundingAcrossUnitBoundaries() {
        assertArrayEquals(new String[]{"0.0","KB/s"},FeaturePolicy.rateParts(0,false,1));
        assertArrayEquals(new String[]{"8.00","Kb/s"},FeaturePolicy.rateParts(1024,true,2));
        assertArrayEquals(new String[]{"1.0","MB/s"},FeaturePolicy.rateParts(1048575,false,1));
    }
    @Test public void leaseRefreshRetainsDisplayOptionsAndDisabledUpload() {
        java.util.Map<String,Object> values=new java.util.HashMap<>();
        values.put("schema",1); values.put("enabled",true); values.put("showUpload",false);
        values.put("hideIdle",false); values.put("revision",7L); values.put("safetyBoot",2); values.put("safetyAt",1000L);
        IndicatorSettings first=new IndicatorSettings(values);
        values.put("safetyAt",16000L);
        IndicatorSettings refreshed=new IndicatorSettings(values);
        assertEquals(first.revision,refreshed.revision);
        assertFalse(refreshed.showUpload); assertFalse(refreshed.hideIdle);
        assertTrue(refreshed.stacked); assertTrue(refreshed.safetyValid(2,20000));
        assertFalse(first.safetyValid(2,100000));
    }
    @Test public void indicatorPositionDefaultsLeftAndAcceptsRight() {
        java.util.Map<String,Object> values=new java.util.HashMap<>();
        assertFalse(new IndicatorSettings(values).right);
        values.put("position","right"); assertTrue(new IndicatorSettings(values).right);
        values.put("position","unknown"); assertFalse(new IndicatorSettings(values).right);
    }
}
