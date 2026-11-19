package com.example.remote_control.clipboard

import org.json.JSONObject

/** Content-independent limits and opt-in rules, shared with focused JVM checks. */
data class ShelfPolicy(val enabled:Boolean=false, val limit:Int=100, val days:Int=7,
    val images:Boolean=true, val excluded:Set<String> = DEFAULT_EXCLUDED, val screenshots:Boolean=true) {
    fun accepts(source:String, sensitive:Boolean, unlocked:Boolean) = enabled && unlocked && !sensitive &&
        source.isNotBlank() && source != "com.example.remote_control" && source !in excluded
    fun json()=JSONObject().put("enabled",enabled).put("limit",limit).put("days",days).put("images",images)
        .put("excluded",org.json.JSONArray(excluded.sorted())).put("screenshots",screenshots)
    companion object {
        const val MAX_TEXT=65536
        const val MAX_IMAGE=8*1024*1024
        const val IMAGE_BUDGET=64L*1024*1024
        const val MAX_PINS=25
        val DEFAULT_EXCLUDED=setOf("com.x8bit.bitwarden","com.onepassword.android","com.agilebits.onepassword","keepass2android.keepass2android","com.kunzisoft.keepass.free","com.dashlane")
        fun parse(j:JSONObject):ShelfPolicy {
            val limit=j.optInt("limit",100);require(limit in setOf(50,100,200)){"Choose 50, 100 or 200 recent clips"}
            val days=j.optInt("days",7);require(days in setOf(1,7,30)){"Choose 1, 7 or 30 days"}
            val a=j.optJSONArray("excluded");val excluded=if(a==null)DEFAULT_EXCLUDED else (0 until a.length()).map{a.getString(it)}.toSet()
            require(excluded.size<=500 && excluded.all{it.length<=200&&it.matches(Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+"))}){"Invalid excluded package"}
            return ShelfPolicy(j.optBoolean("enabled",false),limit,days,j.optBoolean("images",true),excluded,j.optBoolean("screenshots",true))
        }
    }
}
