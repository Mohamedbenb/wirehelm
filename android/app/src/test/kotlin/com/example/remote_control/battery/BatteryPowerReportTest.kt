package com.example.remote_control.battery
import org.junit.Test
import org.junit.Assert.*
class BatteryPowerReportTest {
 @Test fun parsesOnlySelectedUidAndExplicitWindow(){val r=BatteryPowerReport.parse("  UID u0a415: 223 fg: 4\n  Uid u0a279: 9.57\n  UID u0a999: 500\n  Start clock time: 2026-11-13-10-00-00",setOf(10415,10279));assertEquals(2,r.values.size);assertEquals(223.0,r.values[10415]!!,.001);assertEquals("2026-11-13-10-00-00",r.window)}
 @Test fun accountingResetAndNegativeDifferenceAreUnavailable(){val a=BatteryPowerReport("a",mapOf(10415 to 10.0));assertNull(BatteryPowerReport.delta(a,BatteryPowerReport("b",mapOf(10415 to 20.0)),10415));assertNull(BatteryPowerReport.delta(a,BatteryPowerReport("a",mapOf(10415 to 9.0)),10415));assertEquals(2.0,BatteryPowerReport.delta(a,BatteryPowerReport("a",mapOf(10415 to 12.0)),10415)!!,.001)}
 @Test(expected=IllegalStateException::class) fun missingUidIsNotZeroEnergy(){BatteryPowerReport.parse("Start clock time: a\n UID u0a415: 2",setOf(10415,10279))}
 @Test(expected=IllegalStateException::class) fun missingWindowIsNotAssumedComparable(){BatteryPowerReport.parse("UID u0a415: 2",setOf(10415))}
}
