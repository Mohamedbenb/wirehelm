package com.example.remote_control.battery

/** Elapsed time and fuel-gauge accounting; no Android APIs or per-feature energy claims. */
data class BatteryPoint(val wall: Long, val elapsed: Long, val boot: Int, val level: Int,
    val charge: Long?, val plugged: Int, val charging: Boolean, val interactive: Boolean) {
    val onBattery get() = plugged == 0 && !charging
}
class BatterySession(val start: BatteryPoint, val partial: Boolean) {
    var last = start
    var screenOnMs = 0L
    var screenOffMs = 0L
    var counterAdjusted = false
    private var splitChargeKnown = start.charge != null
    private var screenOnCharge = 0L
    private var screenOffCharge = 0L
    var flags: Set<String> = emptySet()
    val featureMs = linkedMapOf<String, Long>()
    var reportingKnown = false
    var unknownActivityMs = 0L
    fun accept(next: BatteryPoint, nextFlags: Set<String>, known: Boolean): Boolean {
        if (next.boot != start.boot || next.elapsed < last.elapsed) return false
        val delta = next.elapsed-last.elapsed
        if (last.interactive) screenOnMs += delta else screenOffMs += delta
        if (!reportingKnown) unknownActivityMs += delta
        for (feature in flags) featureMs[feature] = (featureMs[feature] ?: 0)+delta
        if (next.charge != null && last.charge != null) {
            val loss=last.charge!!-next.charge
            if(last.interactive)screenOnCharge+=loss else screenOffCharge+=loss
            if(loss<0)counterAdjusted=true
        } else splitChargeKnown=false
        last=next; flags=nextFlags;reportingKnown=known
        return true
    }
    val durationMs get() = (last.elapsed-start.elapsed).coerceAtLeast(0)
    val lostPercent get() = (start.level-last.level).coerceAtLeast(0)
    val lostMah: Double? get() = if (start.charge != null && last.charge != null) (start.charge!!-last.charge!!).coerceAtLeast(0)/1000.0 else null
    private fun rate(charge:Long,time:Long):Double? = if(splitChargeKnown&&!counterAdjusted&&time>=60000&&charge>=0)charge/1000.0*3600000/time else null
    val screenOnRate get() = rate(screenOnCharge,screenOnMs)
    val screenOffRate get() = rate(screenOffCharge,screenOffMs)
    val mahPerHour: Double? get() = if (durationMs>=60000) lostMah?.times(3600000.0/durationMs) else null
}

/** Starts partial if monitoring begins mid-discharge; a known power-to-battery edge is complete. */
class BatteryDischargeGate {
    data class Start(val partial:Boolean)
    private var previous:Boolean?=null
    fun observe(onBattery:Boolean):Start? {
        val start=if(onBattery&&previous!=true)Start(previous!=false) else null
        previous=onBattery
        return start
    }
}
