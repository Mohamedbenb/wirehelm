package com.nodecockpit.customization
import org.junit.Assert.*
import org.junit.Test

class GlassSliderGeometryTest {
 private val r=GlassLabRect(10f,20f,100f,200f)
 @Test fun verticalFillIsBottomAnchored(){
  assertEquals(GlassLabRect(10f,170f,100f,50f),GlassLabGeometry.sliderFill(r,.25f,true,false))
  assertEquals(r,GlassLabGeometry.sliderFill(r,1f,true,false))
  assertEquals(0f,GlassLabGeometry.sliderFill(r,0f,true,false).height,0f)
 }
 @Test fun horizontalFillRespectsDirection(){
  assertEquals(GlassLabRect(10f,20f,25f,200f),GlassLabGeometry.sliderFill(r,.25f,false,false))
  assertEquals(GlassLabRect(85f,20f,25f,200f),GlassLabGeometry.sliderFill(r,.25f,false,true))
 }
 @Test fun touchValueAndFillBoundaryAgree(){
  for(p in listOf(0f,.25f,.5f,.75f,1f)){
   assertEquals(p,GlassLabGeometry.sliderProgress(r,50f,20f+(1-p)*200f,true,false),.0001f)
   assertEquals(p,GlassLabGeometry.sliderProgress(r,10f+p*100f,50f,false,false),.0001f)
   assertEquals(p,GlassLabGeometry.sliderProgress(r,110f-p*100f,50f,false,true),.0001f)
  }
 }
 @Test fun indicatorTracksFillAndStaysInsideAtEndpoints(){
  val mid=GlassLabGeometry.sliderIndicator(r,.25f,true,false,8f,10f)
  assertEquals(170f,mid.cy,0f)
  for(p in listOf(0f,1f)){
   val marker=GlassLabGeometry.sliderIndicator(r,p,true,false,8f,10f)
   assertTrue(marker.top>=r.top&&marker.top+marker.height<=r.top+r.height)
  }
 }
 @Test fun invalidProgressIsBounded(){
  assertEquals(0f,GlassLabGeometry.sliderFill(r,Float.NaN,true,false).height,0f)
  assertEquals(r,GlassLabGeometry.sliderFill(r,2f,true,false))
 }
}
