package com.example.remote_control.battery

/** Parses only requested UID estimates and the accounting-window identity. */
data class BatteryPowerReport(val window: String, val values: Map<Int, Double>) {
    companion object {
        private val uid = Regex("""(?im)^\s*uid\s+(?:u(\d+)a(\d+)|(\d+)):\s*([0-9.]+(?:e[+-]?\d+)?)\b""")
        fun parse(text: String, selected: Set<Int>): BatteryPowerReport {
            val window=Regex("""(?m)^\s*Start clock time:\s*(.+)$""").find(text)?.groupValues?.get(1)?.trim() ?: error("Android accounting window unavailable")
            val values=linkedMapOf<Int,Double>()
            for(m in uid.findAll(text)) {
                val id=if(m.groupValues[3].isNotEmpty())m.groupValues[3].toInt() else m.groupValues[1].toInt()*100000+10000+m.groupValues[2].toInt()
                val value=m.groupValues[4].toDouble()
                if(id in selected && value.isFinite() && value>=0)values[id]=value
            }
            check(values.keys.containsAll(selected)){"Android UID energy estimates unavailable"}
            return BatteryPowerReport(window,values)
        }
        fun delta(before: BatteryPowerReport?, after: BatteryPowerReport?, uid: Int): Double? {
            if(before==null||after==null||before.window!=after.window)return null
            val a=before.values[uid] ?: return null;val b=after.values[uid] ?: return null
            return (b-a).takeIf { it>=0 }
        }
    }
}
