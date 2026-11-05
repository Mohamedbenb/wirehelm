package com.nodecockpit.customization;

import android.graphics.Canvas;
import org.junit.Test;
import java.util.ArrayList;
import static org.junit.Assert.*;

public class GlassBrightnessMaterialTest {
    private static final class Fake implements GlassBrightnessMaterial.Backend {
        int draws,closes,visibility;boolean result=true;float opacity;GlassNativeBlurRegion region;
        public boolean draw(Canvas canvas,GlassBrightnessGeometry.Shape shape,GlassNativeBlurRegion region,float opacity,GlassBrightnessMaterial.Role role){draws++;this.region=region;this.opacity=opacity;return result;}
        public void visible(boolean value){visibility+=value?1:-1;}
        public String diagnostics(){return "backend unavailable";}
        public void close(){closes++;}
    }
    private GlassBrightnessGeometry.Shape shape(float x){return GlassBrightnessGeometry.track(x,4,120.25f,40,20,0,false);}
    @Test public void nativePolicyKeepsIndependentFillAndIndicatorBlurAndUnblurredTrailingTrack(){
        GlassNativeBlurRegion fill=GlassBrightnessMaterial.region(GlassBrightnessMaterial.Role.TRACK,shape(0),73,26);
        GlassNativeBlurRegion rest=GlassBrightnessMaterial.region(GlassBrightnessMaterial.Role.TRACK,shape(121),73,26);
        GlassNativeBlurRegion thumb=GlassBrightnessMaterial.region(GlassBrightnessMaterial.Role.INDICATOR,shape(121),73,26);
        GlassNativeBlurRegion base=GlassBrightnessMaterial.region(GlassBrightnessMaterial.Role.CONTAINER,shape(0),73,26);
        assertEquals(73,fill.blur);assertEquals(0,rest.blur);assertEquals(26,thumb.blur);assertEquals(18,base.blur);
        assertEquals(0x18ffffff,fill.tint);assertEquals(0x38ffffff,thumb.tint);assertEquals(0x10ffffff,base.tint);
        assertEquals(121,fill.width);assertEquals(20,fill.tl,0);assertEquals(0,fill.tr,0);
    }
    @Test public void boundedSlotsReuseTheirOwnBackendAcrossMotionAndOpacityChanges(){
        ArrayList<Fake> sessions=new ArrayList<>();
        GlassBrightnessMaterial material=new GlassBrightnessMaterial(()->{Fake f=new Fake();sessions.add(f);return f;},60,60);
        for(int frame=0;frame<30;frame++)assertTrue(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(frame),.5f));
        for(int slot=1;slot<4;slot++)assertTrue(material.draw(null,slot,GlassBrightnessMaterial.Role.INDICATOR,shape(slot),1));
        assertFalse(material.draw(null,4,GlassBrightnessMaterial.Role.TRACK,shape(0),1));
        assertEquals(4,material.createdSessions());assertEquals(30,sessions.get(0).draws);assertEquals(.5f,sessions.get(0).opacity,0);
    }
    @Test public void unavailableBackendIsExplicitAndNotRecreatedOnEveryFrame(){
        int[] attempts={0};GlassBrightnessMaterial material=new GlassBrightnessMaterial(()->{attempts[0]++;throw new IllegalStateException("restricted API");},60,60);
        for(int frame=0;frame<20;frame++)assertFalse(material.draw(null,0,GlassBrightnessMaterial.Role.CONTAINER,shape(0),1));
        assertEquals(1,attempts[0]);assertEquals(0,material.createdSessions());assertTrue(material.diagnostics().contains("restricted API"));
    }
    @Test public void hideAndShowReuseSessionAndNeverDrawWhileHidden(){
        Fake f=new Fake();GlassBrightnessMaterial material=new GlassBrightnessMaterial(()->f,60,60);
        assertTrue(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1));
        material.setVisible(false);assertFalse(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1));assertEquals(1,f.draws);
        material.setVisible(true);assertTrue(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1));assertEquals(1,material.createdSessions());assertEquals(0,f.visibility);
    }
    @Test public void closeReleasesEveryCreatedSessionOnceAndCannotReattach(){
        ArrayList<Fake> sessions=new ArrayList<>();GlassBrightnessMaterial material=new GlassBrightnessMaterial(()->{Fake f=new Fake();sessions.add(f);return f;},60,60);
        for(int slot=0;slot<4;slot++)assertTrue(material.draw(null,slot,GlassBrightnessMaterial.Role.TRACK,shape(0),1));
        material.close();material.close();material.setVisible(false);
        assertFalse(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1));
        for(Fake f:sessions)assertEquals(1,f.closes);
    }
    @Test public void malformedDrawDoesNotCreateOrSuppressStock(){
        int[] attempts={0};GlassBrightnessMaterial material=new GlassBrightnessMaterial(()->{attempts[0]++;return new Fake();},60,60);
        for(float alpha:new float[]{Float.NaN,Float.POSITIVE_INFINITY,-1,2})assertFalse(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),alpha));
        assertFalse(material.draw(null,-1,GlassBrightnessMaterial.Role.TRACK,shape(0),1));assertFalse(material.draw(null,0,null,shape(0),1));assertFalse(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,null,1));assertEquals(0,attempts[0]);
    }
    @Test public void failedDrawIsNotReportedAsApplied(){
        Fake f=new Fake();f.result=false;GlassBrightnessMaterial material=new GlassBrightnessMaterial(()->f,60,60);
        assertFalse(material.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1));assertTrue(material.diagnostics().contains("draws=0"));assertTrue(material.diagnostics().contains("backend unavailable"));
    }
    @Test public void geometryRejectsInvalidNumbersAndKeepsSquareFillEnd(){
        assertNull(GlassBrightnessGeometry.track(Float.NaN,0,100,40,20,0,false));assertNull(GlassBrightnessGeometry.track(0,0,0,40,20,0,false));
        assertNull(GlassBrightnessGeometry.track(0,0,5000,40,20,0,false));assertNull(GlassBrightnessGeometry.track(0,0,100,40,-1,0,false));
        GlassBrightnessGeometry.Shape narrow=GlassBrightnessGeometry.track(0,0,4,40,20,0,false);assertEquals(2,narrow.tl,0);assertEquals(0,narrow.tr,0);
        GlassBrightnessGeometry.Shape vertical=GlassBrightnessGeometry.track(0,0,40,120,20,0,true);assertEquals(20,vertical.tr,0);assertEquals(0,vertical.bl,0);
    }
    @Test public void newConfigurationGetsNewSessionsAndRejectsNonFiniteSettings(){
        Fake previous=new Fake();GlassBrightnessMaterial first=new GlassBrightnessMaterial(()->previous,60,60);first.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1);first.close();
        Fake current=new Fake();GlassBrightnessMaterial next=new GlassBrightnessMaterial(()->current,99,12);next.draw(null,0,GlassBrightnessMaterial.Role.TRACK,shape(0),1);assertEquals(99,current.region.blur);assertEquals(1,previous.closes);
        try{new GlassBrightnessMaterial(()->new Fake(),Float.NaN,1);fail();}catch(IllegalArgumentException expected){}
    }
}
