package com.nodecockpit.customization
import org.junit.Assert.*
import org.junit.Test
class GlassLabInteractionTest {
 private val cards=listOf(GlassLabRect(10f,10f,80f,60f),GlassLabRect(100f,80f,80f,60f))
 @Test fun tapTogglesAndCountsExactlyOnce(){val h=GlassLabInteraction();assertTrue(h.down(7,20f,20f,cards));assertEquals(0,h.up(7,20f,20f,cards,true));assertTrue(h.toggled(0));assertEquals(1,h.clickCount);assertNull(h.up(7,20f,20f,cards,true));assertEquals(1,h.clickCount)}
 @Test fun dragMovesWithoutClickAndClamps(){val h=GlassLabInteraction();assertTrue(h.down(1,20f,20f,cards));h.move(1,500f,500f,cards,300f,200f,true,8f);val moved=h.layout(cards,300f,200f);assertEquals(220f,moved[0].left,0f);assertEquals(140f,moved[0].top,0f);assertNull(h.up(1,500f,500f,moved,true));assertEquals(0,h.clickCount)}
 @Test fun twoPointersMoveDifferentCardsIndependently(){val h=GlassLabInteraction();assertTrue(h.down(4,20f,20f,cards));assertTrue(h.down(8,110f,90f,cards));h.move(4,30f,30f,cards,300f,200f,true,2f);h.move(8,100f,90f,cards,300f,200f,true,2f);val moved=h.layout(cards,300f,200f);assertEquals(20f,moved[0].left,.001f);assertEquals(90f,moved[1].left,.001f);assertEquals(2,h.pointerCount)}
 @Test fun disabledAndOutsideDoNotCapture(){val h=GlassLabInteraction();assertFalse(h.down(1,110f,90f,cards,1));assertFalse(h.down(1,299f,199f,cards));assertEquals(0,h.pointerCount)}
 @Test fun buttonDragAndCancelledTouchNeverToggle(){val h=GlassLabInteraction();h.down(1,20f,20f,cards);h.move(1,40f,20f,cards,300f,200f,false,8f);assertNull(h.up(1,40f,20f,cards,true));h.down(1,20f,20f,cards);h.cancel();assertNull(h.up(1,20f,20f,cards,true));assertFalse(h.toggled(0))}
 @Test fun layoutPreservesNormalizedPositionOnResize(){val h=GlassLabInteraction();h.down(1,20f,20f,cards);h.move(1,120f,90f,cards,300f,200f,true,2f);val before=h.layout(cards,300f,200f);val after=h.layout(cards,500f,300f);assertEquals(before[0].left/(300-80),after[0].left/(500-80),.0001f);assertEquals(before[0].top/(200-60),after[0].top/(300-60),.0001f)}
 @Test fun duplicatePointerAndNonfiniteInputAreRejected(){val h=GlassLabInteraction();assertFalse(h.down(1,Float.NaN,20f,cards));assertTrue(h.down(1,20f,20f,cards));assertFalse(h.down(1,110f,90f,cards));h.move(1,Float.NaN,30f,cards,300f,200f,true,2f);assertEquals(cards,h.layout(cards,300f,200f))}
 @Test fun resetClearsDragAndButtonState(){val h=GlassLabInteraction();h.down(1,20f,20f,cards);h.up(1,20f,20f,cards,true);h.reset();assertFalse(h.toggled(0));assertEquals(0,h.clickCount);assertEquals(-1,h.selected);assertEquals(cards,h.layout(cards,300f,200f))}
 @Test fun removedCardsReleaseTheirPointers(){val h=GlassLabInteraction();assertTrue(h.down(8,110f,90f,cards));h.layout(cards.take(1),300f,200f);assertEquals(0,h.pointerCount);assertEquals(-1,h.selected)}
 @Test fun positionsRestoreWithoutPressedPointers(){val h=GlassLabInteraction();h.down(1,20f,20f,cards);h.move(1,120f,90f,cards,300f,200f,true,2f);val expected=h.layout(cards,300f,200f);val restored=GlassLabInteraction();restored.restorePositions(h.savePositions());assertEquals(expected,restored.layout(cards,300f,200f));assertEquals(0,restored.pointerCount)}
 @Test fun invalidSavedPositionsPreserveExistingPositions(){val h=GlassLabInteraction();h.restorePositions(floatArrayOf(0f,.5f,.5f));val before=h.savePositions();for(bad in listOf(floatArrayOf(0f),floatArrayOf(0f,Float.NaN,.5f),floatArrayOf(17f,.5f,.5f),floatArrayOf(.5f,.5f,.5f))){try{h.restorePositions(bad);fail("Invalid positions accepted")}catch(expected:IllegalArgumentException){};assertArrayEquals(before,h.savePositions(),0f)}}
}

