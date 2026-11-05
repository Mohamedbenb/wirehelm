package com.nodecockpit.customization

/** Catalog shared by controls, state validation and coverage tests. No Android dependency. */
object GlassLabCatalog {
 data class Control(val key:String,val label:String,val group:String,val low:Float,val high:Float,val initial:Float,val unit:String="")
 val controls=listOf(
  Control("blurStrength","Material blur","Optics",0f,100f,20f),Control("refraction","Refraction","Optics",0f,240f,40f),
  Control("bevel","Bevel","Optics",4f,160f,32f),Control("falloff","Falloff","Optics",0f,6f,2f),
  Control("dispersion","Dispersion","Optics",0f,.9f,.1f),Control("specular","Specular","Optics",0f,2f,1f),
  Control("softness","Rim softness","Optics",0f,24f,0f),Control("saturation","Saturation","Optics",0f,200f,140f),
  Control("baseVeil","Clear veil","Tint",0f,100f,8f),Control("regularToneStrength","Regular tone","Tint",0f,100f,70f),
  Control("dimming","Dimming","Tint",0f,100f,0f),Control("glassTintStrength","Tint strength","Tint",0f,1f,0f),
  Control("progress","Progress","Masks",0f,1f,.55f),Control("progressBlur","Progress blur","Masks",0f,100f,60f),
  Control("indicatorBlur","Indicator blur","Masks",0f,100f,60f),Control("pillBlur","Notification pill blur","Masks",0f,100f,40f),
  Control("radius","Radius","Geometry",0f,100f,32f,"dp"),Control("cornerTL","Top left radius","Geometry",0f,100f,32f,"dp"),
  Control("cornerTR","Top right radius","Geometry",0f,100f,12f,"dp"),Control("cornerBR","Bottom right radius","Geometry",0f,100f,32f,"dp"),Control("cornerBL","Bottom left radius","Geometry",0f,100f,12f,"dp"),
  Control("regionAlpha","Alternate region alpha","Geometry",0f,1f,1f),Control("regionClip","Per-region clip (QS)","Geometry",0f,1f,1f),Control("count","Region count","Geometry",1f,16f,4f),Control("merge","Merge distance","Geometry",0f,100f,24f,"dp"),Control("separation","Union separation","Geometry",0f,1f,.6f),
  Control("width","Width","Geometry",.2f,1f,.9f),Control("height","Height","Geometry",.15f,.9f,.4f),Control("offset","Position","Motion",0f,1f,.4f),
  Control("secondaryWidth","Secondary width","Geometry",.2f,1f,1f),Control("secondaryHeight","Secondary height","Geometry",.2f,1f,1f),
  Control("alpha","Material alpha","Motion",0f,1f,1f),Control("scale","Scale","Motion",.3f,1.3f,1f),Control("rotation","Rotation","Motion",-30f,30f,0f),Control("clip","Clip fraction","Motion",0f,1f,1f),Control("speed","Motion duration","Motion",400f,4000f,1600f,"ms"),
  Control("outlineWidth","Outline width","Foreground",0f,3f,.65f,"dp"),Control("outlineOpacity","Outline opacity","Foreground",0f,100f,100f),
  Control("shadowRadius","Shadow size","Foreground",0f,8f,1.5f,"dp"),Control("shadowOpacity","Shadow opacity","Foreground",0f,100f,44f),
  Control("shadowX","Shadow X","Foreground",-6f,6f,0f,"dp"),Control("shadowY","Shadow Y","Foreground",-6f,6f,.5f,"dp"),Control("font","Font size","Foreground",12f,32f,17f,"sp"),
  Control("dragSlop","Host drag threshold","Touch",2f,24f,8f,"dp"),Control("reactionIntensity","Reaction","Touch",0f,1f,.25f),Control("rippleStrength","Ripple strength","Touch",0f,1f,.5f),Control("rippleSpeed","Ripple speed","Touch",.25f,2.5f,1f),Control("rippleDamping","Ripple damping","Touch",.3f,3f,1.4f),
  Control("lightAngle","Light direction","Lighting",0f,360f,235f),
  Control("classicPreset","Classic preset","Classic",0f,3f,3f),Control("classicBlur","Classic blur","Classic",0f,12f,2.2f),Control("classicRefraction","Classic refraction","Classic",0f,12f,4f),Control("classicTint","Classic tint","Classic",0f,.6f,.035f),Control("classicEdge","Classic edge","Classic",0f,1f,.42f),Control("classicContrast","Classic contrast","Classic",0f,1f,.6f),
  Control("policyLuma","Known backdrop luminance","Policy probe",0f,1f,.5f),Control("policySurround","Surrounding luminance","Policy probe",0f,1f,.5f),Control("toneDuration","Tone duration (-1 = damped)","Policy probe",-1f,2000f,-1f)) + MaterialTuning.RANGES.map{(key,range)->Control("policy.$key",key,"Policy tuning",range[0].toFloat(),range[1].toFloat(),range[2].toFloat())}
 val byKey=controls.associateBy{it.key}
 val profiles=listOf("Local lens","Compositor card","Two-shape merge","Notification union","QS / brightness","Classic material")
 val scenes=listOf("Slider","Rounded card","Circle","Asymmetric corners","Merged pair","Region grid","Movable cards","Glass buttons")
 val motions=listOf("Stopped","Translate","Resize","Fade / hide","Scale / rotate","Progress sweep","Background motion","Profile / page changes","Stress cycle")
 val backgrounds=listOf("Dark pattern","Light pattern","Checkerboard","Text / contrast","Color gradient")
 val flags=listOf("controlMaskPreview","verticalSlider","kawasePreblur","androidBlur","regular","outward","pressEffects","reactionEnabled","touchRipples","sensorLighting","rtl","asymmetric","outlineAuto","shadowAuto","autoInk","darkInk","border","forceFallback","reduceMotion","paused","metrics","widgets","performanceHud","simulatePowerSave","simulateThermal","policyProbe","policyConstrainOther","dragCards","disableLastButton")
 fun supportedScenes(profile:Int)=when(profile){1->listOf(0,1,2,3);2->listOf(4,1,2,6,7);3->listOf(5,0,1,2,6,7);5->listOf(1,2,0);else->scenes.indices.toList()}
 val defaults=mapOf("pressEffects" to true,"reactionEnabled" to true,"touchRipples" to true,"outlineAuto" to true,"shadowAuto" to true,"border" to true,"metrics" to true,"widgets" to true,"dragCards" to true)
 val colors=listOf("glassTintColor","inkColor","outlineColor","shadowColor")
}
class GlassLabState {
 private val values=mutableMapOf<String,Float>()
 private val flags=mutableMapOf<String,Boolean>()
 private val colors=mutableMapOf<String,Int>()
 var profile=0; var scene=0; var motion=0; var background=0; var text="Brightness · مرحبا · 42"
 fun number(key:String):Float=values[key]?:GlassLabCatalog.byKey.getValue(key).initial
 fun setNumber(key:String,value:Float){val c=GlassLabCatalog.byKey.getValue(key);values[key]=(if(value.isFinite())value else c.initial).coerceIn(c.low,c.high)}
 fun flag(key:String)=flags[key]?:GlassLabCatalog.defaults[key]?:false
 fun setFlag(key:String,value:Boolean){require(key in GlassLabCatalog.flags);flags[key]=value}
 fun color(key:String):Int=colors[key]?:if(key in listOf("inkColor","glassTintColor")) -1 else 0xff000000.toInt()
 fun setColor(key:String,value:Int){require(key in GlassLabCatalog.colors);colors[key]=value or 0xff000000.toInt()}
 fun reset(){values.clear();flags.clear();colors.clear();profile=0;scene=0;motion=0;background=0;text="Brightness · مرحبا · 42"}
 fun copy():GlassLabState=GlassLabState().also{it.values.putAll(values);it.flags.putAll(flags);it.colors.putAll(colors);it.profile=profile;it.scene=scene;it.motion=motion;it.background=background;it.text=text}
 fun validateSelections(){profile=profile.coerceIn(0,GlassLabCatalog.profiles.lastIndex);scene=scene.coerceIn(0,GlassLabCatalog.scenes.lastIndex);motion=motion.coerceIn(0,GlassLabCatalog.motions.lastIndex);background=background.coerceIn(0,GlassLabCatalog.backgrounds.lastIndex);text=text.take(256)}
}
