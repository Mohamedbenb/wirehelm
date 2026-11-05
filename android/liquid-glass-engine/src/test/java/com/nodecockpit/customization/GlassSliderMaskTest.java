package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassSliderMaskTest {
 @Test public void fillUsesStraightCutoffInBothDirections(){assertArrayEquals(new float[]{10,20,50,40},GlassSliderGeometry.fill(10,20,200,40,.25f,false,false),0);assertArrayEquals(new float[]{160,20,50,40},GlassSliderGeometry.fill(10,20,200,40,.25f,false,true),0);assertArrayEquals(new float[]{10,50,200,10},GlassSliderGeometry.fill(10,20,200,40,.25f,true,false),0);}
 @Test public void maskKeepsFullCardAndIndependentFillCutoff(){float[] m=GlassSliderGeometry.mask(10,20,200,40,.25f,100,24,1,15,22,190,58);assertArrayEquals(new float[]{110,40,100,20,.25f,20,24,1,15,22,190,58},m,0);}
 @Test public void fractionsAreBounded(){assertEquals(0,GlassSliderGeometry.fraction(Float.NaN),0);assertEquals(0,GlassSliderGeometry.fraction(-1),0);assertEquals(1,GlassSliderGeometry.fraction(2),0);}
 @Test(expected=IllegalArgumentException.class) public void emptyMaskIsRejected(){GlassSliderGeometry.mask(0,0,0,20,1,10,20,0,0,0,10,20);}
 @Test(expected=IllegalArgumentException.class) public void nonfiniteMaskIsRejected(){GlassSliderGeometry.mask(Float.NaN,0,100,20,1,10,20,0,0,0,100,20);}
}
