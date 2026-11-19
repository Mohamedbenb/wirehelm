package com.example.remote_control.battery
import org.junit.Test
import org.junit.Assert.*
class BatteryCustomizationTest {
 @Test fun absentOrOldBootReportDoesNotInventActivity(){val r=BatteryCustomizationSource.parse(mapOf("hookBoot" to "1","hookPid" to "30","enabled" to "true","hookMetrics" to "{\"visible\":true}"),true,2);assertFalse(r.known);assertTrue(r.flags.isEmpty())}
 @Test fun ringOnlyCountsReportedAmbientShowing(){val v=mapOf("hookBoot" to "1","hookPid" to "30","cameraRing" to "{\"enabled\":true}","hookMetrics" to "{\"cameraRing\":\"state=showing,winner=test\"}");assertTrue(BatteryCustomizationSource.parse(v,false,1).flags.contains("Notification ring"));assertFalse(BatteryCustomizationSource.parse(v,true,1).flags.contains("Notification ring"))}
 @Test fun configurationSummaryHasNoMessageOrRawHealthContent(){val v=mapOf("enabled" to "true","interval" to "1000");val r=BatteryCustomizationSource.parse(v,true,1);assertEquals("On · 1000 ms",r.summary["Network indicator"]);assertFalse(r.summary.containsKey("hookMetrics"))}
}
