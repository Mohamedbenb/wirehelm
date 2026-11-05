package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class TextToneTest {
 @Test public void endpointsAndIntermediateShadesAreOpaqueAndContinuous(){
  assertEquals(0xff000000,TextTone.color(0));assertEquals(0xffffffff,TextTone.color(100));assertEquals(0xff808080,TextTone.color(50));
  int last=-1;for(int i=0;i<=100;i++){int c=TextTone.color(i);assertEquals(255,c>>>24);assertEquals(c&255,(c>>>8)&255);assertEquals(c&255,(c>>>16)&255);assertTrue((c&255)>last);last=c&255;}
 }
 @Test public void defaultSentinelAndBoundsAreValidated(){assertTrue(TextTone.valid(-1));assertTrue(TextTone.valid(100));assertFalse(TextTone.valid(-2));assertFalse(TextTone.valid(101));}
 @Test public void panelToneOnlyChangesItsVisualSignature(){
  IndicatorSettings nativeTone=new IndicatorSettings(java.util.Map.of()),custom=new IndicatorSettings(java.util.Map.of("edgePanelTextTone",50));
  assertEquals(-1,nativeTone.edgePanelTextTone);assertEquals(50,custom.edgePanelTextTone);
  assertNotEquals(nativeTone.edgeVisualSignature(),custom.edgeVisualSignature());assertEquals(nativeTone.edgeContentSignature(),custom.edgeContentSignature());assertEquals(nativeTone.edgeGeometrySignature(),custom.edgeGeometrySignature());assertTrue(SavedSetupScope.owns("edge","edgePanelTextTone"));
 }
}
