package com.example.remote_control.battery

import android.content.Context
import android.app.ActivityManager
import android.util.Xml
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.File

data class BatteryCustomization(val summary: Map<String,String>,val flags: Set<String>,val known: Boolean,val rootApproved: Boolean)
object BatteryCustomizationSource {
    private val cache=mutableMapOf<String,Map<String,String>>()
    @Synchronized private fun prefs(file:File,selected:Set<String>?):Map<String,String>{
        return try {
            val values=mutableMapOf<String,String>()
            file.inputStream().use{input->
                val p=Xml.newPullParser();p.setInput(input,"UTF-8");var complete=false
                while(p.eventType!=XmlPullParser.END_DOCUMENT){
                    if(p.eventType==XmlPullParser.END_TAG&&p.name=="map")complete=true
                    if(p.eventType==XmlPullParser.START_TAG){val name=p.getAttributeValue(null,"name")
                        if(name!=null&&(selected==null||name in selected))values[name]=p.getAttributeValue(null,"value") ?: p.nextText()
                    };p.next()
                }
                check(complete){"Preference write in progress"}
            }
            cache[file.path]=values;values
        }catch(_:Exception){cache[file.path] ?: emptyMap()}
    }
    fun read(context: Context, interactive: Boolean, boot: Int): BatteryCustomization {
        val selected=setOf("enabled","interval","edgePanelEnabled","edgePanelNativeGlass","edgePanelBlur","edgePanelOpacity","cameraRing","notificationUndo","hookMetrics","hookBoot","hookPid","rootApproved","carrierRootSnapshot")
        val dir=File(context.createDeviceProtectedStorageContext().dataDir,"shared_prefs")
        val result=parse(prefs(File(dir,"local_customization_v1.xml"),selected),interactive,boot)
        val ce=File(context.dataDir,"shared_prefs")
        val buttons=prefs(File(ce,"screen_off_buttons.xml"),null).count{(key,value)->
            (key=="up"||key=="down"||key.startsWith("up_")||key.startsWith("down_")||key.startsWith("power_"))&&value.isNotEmpty()&&value!="none"
        }
        val rules=runCatching{JSONObject(prefs(File(ce,"app_network.xml"),setOf("rules"))["rules"] ?: "{}").length()}.getOrDefault(0)
        val contextFlags=linkedSetOf<String>()
        @Suppress("DEPRECATION")
        val services=runCatching{context.getSystemService(ActivityManager::class.java).getRunningServices(100)}.getOrDefault(emptyList())
        for(service in services)if(service.uid==context.applicationInfo.uid&&service.foreground){
            when(service.service.className.substringAfterLast('.')){
                "AdbRelayService"->contextFlags.add("Remote ADB")
                "KeepAliveService"->contextFlags.add("SSH keep-alive")
                "ButtonShortcutService"->contextFlags.add("Button monitor")
            }
        }
        return result.copy(summary=result.summary+mapOf("Button bindings" to buttons.toString(),"Saved firewall rules" to rules.toString()),flags=result.flags+contextFlags)
    }
    fun parse(v: Map<String,String>, interactive: Boolean, boot: Int): BatteryCustomization {
        fun obj(key:String)=runCatching{JSONObject(v[key] ?: "{}")}.getOrElse{JSONObject()}
        fun on(key:String)=v[key]=="true"
        val ring=obj("cameraRing");val undo=obj("notificationUndo");val glass=obj("edgePanelNativeGlass")
        val carrier=obj("carrierRootSnapshot");val metrics=obj("hookMetrics");val flags=linkedSetOf<String>()
        val known=boot>=0&&v["hookBoot"]?.toIntOrNull()==boot&&(v["hookPid"]?.toIntOrNull() ?: 0)>0
        if(known){
            if(interactive&&metrics.optBoolean("visible")&&on("enabled"))flags.add("Network indicator")
            val edge=metrics.optString("edgePanel")
            val progress=Regex("""(?:^|,)progress=([0-9.]+)""").find(edge)?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
            if(interactive&&on("edgePanelEnabled")&&edge.isNotEmpty()){
                if(progress>0)flags.add("Edge panel")
                else if(edge.contains("state=CLOSED")&&!edge.contains("guard=blocked"))flags.add("Edge handle")
            }
            if(!interactive&&ring.optBoolean("enabled")&&metrics.optString("cameraRing").startsWith("state=showing,"))flags.add("Notification ring")
            if(metrics.optString("notificationUndo").contains("shakeListening=true"))flags.add("Shake Undo")
        }
        val summary=linkedMapOf(
            "Network indicator" to if(on("enabled"))"On · ${v["interval"] ?: "1000"} ms" else "Off",
            "Edge panel" to if(on("edgePanelEnabled"))"On · ${glass.optString("engine","native")} material" else "Off",
            "Live handle glass" to if(glass.optBoolean("liveHandle"))"On" else "Off",
            "Panel blur" to if(glass.optString("engine")=="card")(glass.optJSONObject("cardMaterial")?.optDouble("blurStrength",0.0)?.toString() ?: "Default") else (v["edgePanelBlur"] ?: "0"),
            "Notification ring" to if(ring.optBoolean("enabled"))"On · ${ring.optInt("intensity",100)}% · ${ring.optInt("intervalMs",1000)} ms fade" else "Off",
            "Ring without AOD" to if(ring.optBoolean("ambientOnDemand"))"On" else "Off",
            "Ring thickness" to "${ring.optInt("thickness",3)} dp",
            "Carrier override (last check)" to carrier.optString("moduleState","Unknown"),
            "Notification Undo" to if(undo.optBoolean("enabled"))"On · shake ${if(undo.optBoolean("shake"))"on" else "off"}" else "Off"
        )
        return BatteryCustomization(summary,flags,known,on("rootApproved"))
    }
}
