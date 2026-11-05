package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.*;
public class MaterialTuningTest {
 @Test public void absentTuningIsAnIdentityForExistingProfiles() { assertFalse(MaterialTuning.DEFAULT.enabled);for(float n:new float[]{0,.2f,.5f,.9f,1})assertEquals(GlassTransitionMath.tone(n),MaterialTuning.DEFAULT.tone(n),.00001);assertEquals(0x55123456,MaterialTuning.DEFAULT.tint(0x55123456));assertEquals(0x55123456,MaterialTuning.DEFAULT.border(0x55123456)); }
 @Test public void enablingDefaultTuningPreservesTheShippingToneCurve() { MaterialTuning t=new MaterialTuning(Map.of("enabled",true));for(float n:new float[]{0,.2f,.5f,.9f,1})assertEquals(GlassTransitionMath.tone(n),t.tone(n),.00001); }
 @Test public void saturationChangesTintNotAlpha() { MaterialTuning t=new MaterialTuning(Map.of("enabled",true,"saturation",0));int c=t.tint(0x551234ef);assertEquals(0x55,c>>>24);assertEquals((c>>16)&255,(c>>8)&255);assertEquals((c>>8)&255,c&255); }
 @Test public void borderBiasChangesBrightnessNotOpacity() { MaterialTuning t=new MaterialTuning(Map.of("enabled",true,"borderLuminance",100));assertEquals(0x55ffffff,t.border(0x55123456)); }
 @Test public void invalidTypesRangesAndInvertedRegionsAreRejected() { assertTrue(MaterialTuning.valid(Map.of()));assertFalse(MaterialTuning.valid(Map.of("enabled","true")));assertFalse(MaterialTuning.valid(Map.of("saturation",201)));assertFalse(MaterialTuning.valid(Map.of("saturation",Double.NaN)));assertFalse(MaterialTuning.valid(Map.of("sampleTop",90,"sampleBottom",20)));assertFalse(MaterialTuning.valid(Map.of("darkThreshold",70,"lightThreshold",60)));assertFalse(MaterialTuning.valid(Map.of("unknown",1))); }
 @Test public void contrastGuardPreventsBiasedUnreadableText() { for(float l:new float[]{0,.1f,.9f,1})assertEquals(GlassContrast.foreground(0,l,0),GlassContrast.foreground(0,l,0,4.5,1.15,.2)); }
 @Test public void regionCropStaysLocalOrderedAndInsideDisplay() {
  MaterialTuning t=new MaterialTuning(Map.of("enabled",true,"sampleLeft",25,"sampleTop",25,"sampleRight",75,"sampleBottom",75));
  assertArrayEquals(new int[]{125,150,175,250},t.crop(100,100,200,300,1,0,0,1080,2400));
  MaterialTuning expand=new MaterialTuning(Map.of("enabled",true,"samplePaddingDp",48));
  assertArrayEquals(new int[]{0,0,1080,2400},expand.crop(0,0,1080,2400,3,0,0,1080,2400));
  assertArrayEquals(new int[]{1079,2399,1080,2400},t.crop(2000,3000,2100,3100,1,0,0,1080,2400));
 }
 @Test public void visualTuningDoesNotRecreateSamplingSubscriptions() {
  MaterialTuning current=new MaterialTuning(Map.of("enabled",true));
  assertFalse(new MaterialTuning(Map.of("enabled",true,"saturation",130,"textHoldMs",150)).samplingChanged(current));
  assertTrue(new MaterialTuning(Map.of("enabled",true,"sampleTop",20)).samplingChanged(current));
  assertTrue(new MaterialTuning(Map.of("enabled",true,"showRegions",true)).samplingChanged(current));
  assertFalse(new MaterialTuning(Map.of("saturation",140,"sampleTop",20)).samplingChanged(MaterialTuning.DEFAULT));
 }
 @Test public void exponentialTransitionsAreFrameRateIndependent() { float a=1-(float)Math.pow(1-GlassTransitionMath.amount(16,72),10),b=GlassTransitionMath.amount(160,72);assertEquals(a,b,.0001); }
 @Test public void dynamicInkIsExplicitAndValidated() {
  assertFalse(MaterialTuning.DEFAULT.dynamicText);
  assertTrue(MaterialTuning.valid(java.util.Map.of("dynamicText",true)));
  assertFalse(MaterialTuning.valid(java.util.Map.of("dynamicText",1)));
  assertTrue(new MaterialTuning(java.util.Map.of("dynamicText",true)).dynamicText);
 }
}
