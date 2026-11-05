package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class SmoothInkToneTest {
 private static int tone(int color){return color&255;}
 private static int settle(SmoothInkTone ink,float luma){int value=0;for(int i=0;i<100;i++)value=ink.step(0,luma,luma,luma,0,false,16,MaterialTuning.DEFAULT);return value;}
 @Test public void usesContinuousReadableGreyRatherThanBinaryEndpoints(){
  SmoothInkTone p=new SmoothInkTone();p.seed(0xff000000);int color=settle(p,.85f);
  assertTrue(tone(color)>10&&tone(color)<120);assertTrue(GlassContrast.contrast(color,0,.85f)>=4.5);assertTrue(p.settled());
 }
 @Test public void severeLossIsCorrectedDuringAChangingBackground(){
  SmoothInkTone p=new SmoothInkTone();p.seed(0xff000000);
  int unreadableFrames=0;for(int i=0;i<300;i++){float luma=(float)(.5+.49*Math.sin(i*.04));int color=p.step(0,luma,1-luma,luma,0,false,16,MaterialTuning.DEFAULT);unreadableFrames=GlassContrast.contrast(color,0,luma)<1.6?unreadableFrames+1:0;assertTrue("contrast recovery at frame "+i,unreadableFrames<=6);}
 }
 @Test public void surroundingsCannotOverrideLocalReadability(){
  SmoothInkTone p=new SmoothInkTone();p.seed(0xffffffff);int color=p.step(0,.01f,1,.01f,0,false,16,MaterialTuning.DEFAULT);
  assertTrue(tone(color)>128);assertTrue(GlassContrast.contrast(color,0,.01f)>=4.5);
  assertEquals(.15f,SmoothInkTone.context(0,1),.0001f);
 }
 @Test public void independentCardsCanHaveDifferentShades(){
  SmoothInkTone a=new SmoothInkTone(),b=new SmoothInkTone();assertTrue(tone(settle(a,.95f))<128);assertTrue(tone(settle(b,.02f))>128);
 }
 @Test public void moderateRawLagDoesNotBypassTheStabilityFilter(){
  SmoothInkTone p=new SmoothInkTone();int start=settle(p,.9f);p.seed(start);
  int color=p.step(0,.9f,.9f,.01f,0,false,16,MaterialTuning.DEFAULT);
  assertTrue(GlassContrast.contrast(start,0,.01f)>=1.6);
  assertTrue(Math.abs(tone(color)-tone(start))<8);
  assertTrue(GlassContrast.contrast(settle(p,.01f),0,.01f)>=4.5);
 }
 @Test public void samePolarityChangesAreGradualAndConverge(){
  SmoothInkTone p=new SmoothInkTone();int start=settle(p,.9f);int next=p.step(0,.55f,.55f,.55f,0,false,16,MaterialTuning.DEFAULT),end=settle(p,.55f);
  assertTrue(tone(next)<tone(start));assertTrue(tone(next)>tone(end));assertTrue(p.settled());
 }
 @Test public void exponentialTrackingDoesNotDependOnFrameRate(){
  SmoothInkTone a=new SmoothInkTone(),b=new SmoothInkTone();a.seed(0xff000000);b.seed(0xff000000);int x=0,y=0;
  for(int i=0;i<20;i++)x=a.step(0,.8f,.8f,.8f,0,false,16,MaterialTuning.DEFAULT);
  for(int i=0;i<40;i++)y=b.step(0,.8f,.8f,.8f,0,false,8,MaterialTuning.DEFAULT);
  assertEquals(tone(x),tone(y),2);
 }
 @Test public void iconAndLabelShareReadableShadeOnBothSurfaces(){
  SmoothInkTone p=new SmoothInkTone();int color=p.step(0,.9f,.9f,.9f,0x66808080,true,16,MaterialTuning.DEFAULT);
  assertFalse(p.limited());assertTrue(GlassContrast.contrast(color,0,.9f)>=4.5);assertTrue(GlassContrast.contrast(color,0x66808080,.9f)>=4.5);
 }
 @Test public void impossibleDualSurfaceContrastIsExplicitlyLimited(){
  SmoothInkTone p=new SmoothInkTone();p.step(0xff000000,.5f,.5f,.5f,0xffffffff,true,16,new MaterialTuning(java.util.Map.of("enabled",true,"minimumContrast",700)));
  assertTrue(p.limited());
 }
 @Test public void moderateLossUsesSmoothCorrectionRatherThanAProjectionJump(){
  SmoothInkTone p=new SmoothInkTone();p.seed(0xff666666);
  int next=p.step(0,.7f,.7f,.7f,0,false,16,MaterialTuning.DEFAULT);
  assertTrue("moderate change should move a few shades",Math.abs(tone(next)-102)<12);
  assertTrue(GlassContrast.contrast(settle(p,.7f),0,.7f)>=4.5);
 }
 @Test public void emergencyCorrectionDoesNotFightTheFilteredTarget(){
  SmoothInkTone p=new SmoothInkTone();p.seed(0xff000000);
  int first=0;for(int i=0;i<7;i++)first=p.step(0,.9f,.9f,.01f,0,false,16,MaterialTuning.DEFAULT);
  for(int i=0;i<30;i++){int next=p.step(0,.9f,.9f,.01f,0,false,16,MaterialTuning.DEFAULT);assertTrue(GlassContrast.contrast(next,0,.01f)>=3);}
  assertTrue(GlassContrast.contrast(first,0,.01f)>=3);
 }
 @Test public void isolatedAndAlternatingRawOutliersDoNotFlashStaticInk(){SmoothInkTone p=new SmoothInkTone();int baseline=settle(p,.9f);p.duration(2000);p.seed(baseline);for(int i=0;i<100;i++){int next=p.step(0,.9f,.9f,i%2==0?.001f:.9f,0,false,16,MaterialTuning.DEFAULT);assertTrue(Math.abs(tone(next)-tone(baseline))<=2);}assertEquals(0,p.repairs());}
 @Test public void sustainedSevereLossStillRepairsWithinOneTenthSecond(){SmoothInkTone p=new SmoothInkTone();p.duration(2000);p.seed(0xff000000);int next=0;for(int i=0;i<6;i++)next=p.step(0,.9f,.9f,.001f,0,false,16,MaterialTuning.DEFAULT);assertTrue(GlassContrast.contrast(next,0,.001f)>=3);assertEquals(1,p.repairs());}
 @Test public void stableBackgroundStopsFrames(){
  SmoothInkTone p=new SmoothInkTone();settle(p,.4f);assertTrue(p.settled());int one=p.step(0,.4f,.4f,.4f,0,false,16,MaterialTuning.DEFAULT);int two=p.step(0,.4f,.4f,.4f,0,false,16,MaterialTuning.DEFAULT);assertEquals(one,two);assertTrue(p.settled());
 }
}
