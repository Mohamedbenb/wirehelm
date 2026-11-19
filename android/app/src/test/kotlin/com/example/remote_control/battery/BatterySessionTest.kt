package com.example.remote_control.battery
import org.junit.Test
import org.junit.Assert.*
class BatterySessionTest {
 private fun point(t:Long,charge:Long?=5000000,interactive:Boolean=true,boot:Int=1,plugged:Int=0,charging:Boolean=false)=BatteryPoint(100000+t,t,boot,if(t==0L)100 else 99,charge,plugged,charging,interactive)
 @Test fun counterAndRateUseElapsedTime(){val s=BatterySession(point(0),false);s.accept(point(3600000,4950000),emptySet(),true);assertEquals(50.0,s.lostMah!!,.0001);assertEquals(50.0,s.mahPerHour!!,.0001);assertEquals(3600000L,s.screenOnMs)}
 @Test fun screenAndFeatureIntervalsAreSplitAtTransitions(){val s=BatterySession(point(0),false);s.flags=setOf("Network");s.reportingKnown=true;s.accept(point(1000,interactive=false),setOf("Ring"),true);s.accept(point(3000,interactive=true),emptySet(),true);assertEquals(1000L,s.screenOnMs);assertEquals(2000L,s.screenOffMs);assertEquals(1000L,s.featureMs["Network"]);assertEquals(2000L,s.featureMs["Ring"])}
 @Test fun rebootOrBackwardsClockDoesNotInventTime(){val s=BatterySession(point(100),true);assertFalse(s.accept(point(200,boot=2),emptySet(),true));assertFalse(s.accept(point(99),emptySet(),true));assertEquals(0L,s.durationMs)}
 @Test fun missingCounterDoesNotInventMah(){val s=BatterySession(point(0,charge=null),false);s.accept(point(60000),emptySet(),true);assertNull(s.lostMah);assertNull(s.mahPerHour)}
 @Test fun gaugeIncreaseIsFlaggedAndNeverNegativeDrain(){val s=BatterySession(point(0),false);s.accept(point(60000,5100000),emptySet(),true);assertTrue(s.counterAdjusted);assertEquals(0.0,s.lostMah!!,.0001)}
 @Test fun shortIntervalsDoNotReportNoisyHourlyRate(){val s=BatterySession(point(0),false);s.accept(point(1000,4999000),emptySet(),true);assertNull(s.mahPerHour)}
 @Test fun suppliedPowerPausesEvenWhenFullOrChargeLimited(){assertFalse(point(0,plugged=1).onBattery);assertFalse(point(0,charging=true).onBattery);assertTrue(point(0).onBattery)}
 @Test fun screenOffRateHasItsOwnChargeAndDuration(){val s=BatterySession(point(0),false);s.accept(point(3600000,4900000,interactive=false),emptySet(),true);s.accept(point(7200000,4880000,interactive=true),emptySet(),true);assertEquals(100.0,s.screenOnRate!!,.001);assertEquals(20.0,s.screenOffRate!!,.001)}
 @Test fun firstMidDischargeIsPartialAndNextUnplugComplete(){val g=BatteryDischargeGate();assertTrue(g.observe(true)!!.partial);assertNull(g.observe(true));assertNull(g.observe(false));assertFalse(g.observe(true)!!.partial)}
 @Test fun startingWhileChargingWaitsForUnplug(){val g=BatteryDischargeGate();assertNull(g.observe(false));assertNull(g.observe(false));assertFalse(g.observe(true)!!.partial)}
}
