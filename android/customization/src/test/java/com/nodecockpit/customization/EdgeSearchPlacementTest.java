package com.nodecockpit.customization;
import org.junit.Test;import static org.junit.Assert.*;
public class EdgeSearchPlacementTest {
 @Test public void requestedDimensionsAreIndependentAndClampToAvailableSpace(){assertEquals(300,EdgeSearchPlacement.size(300,200,500,8));assertEquals(384,EdgeSearchPlacement.size(900,200,400,8));assertEquals(284,EdgeSearchPlacement.size(600,520,300,8));}
 @Test public void automaticSizeUsesExistingFallbackWithoutChangingIt(){assertEquals(236,EdgeSearchPlacement.size(0,236,400,8));assertEquals(1,EdgeSearchPlacement.size(0,520,10,8));}

 @Test public void clampedBeforeScreenAndAboveKeyboard(){assertEquals(8,EdgeSearchPlacement.clamp(-50,400,160,8),0);assertEquals(232,EdgeSearchPlacement.clamp(900,400,160,8),0);assertEquals(92,EdgeSearchPlacement.clamp(500,400,300,8),0);}
 @Test public void positionRoundTripsAndAdaptsToResize(){float f=EdgeSearchPlacement.fraction(120,400,160,8);assertEquals(120,EdgeSearchPlacement.position(f,400,160,8),.001);float resized=EdgeSearchPlacement.position(f,300,160,8);assertTrue(resized>=8&&resized<=132);}
 @Test public void oversizedAndZeroTravelStayBounded(){assertEquals(8,EdgeSearchPlacement.clamp(99,100,140,8),0);assertEquals(0,EdgeSearchPlacement.fraction(99,100,140,8),0);assertEquals(8,EdgeSearchPlacement.position(.7f,100,140,8),0);}
}
