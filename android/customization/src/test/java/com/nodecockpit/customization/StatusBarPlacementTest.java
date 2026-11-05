package com.nodecockpit.customization;

import org.junit.Test;
import static org.junit.Assert.*;

public final class StatusBarPlacementTest {
    @Test public void movesBeforeNewSystemIconAndRestoresPreferredPosition() {
        assertEquals(662,StatusBarPlacement.resolve(700,84,0,1080,new int[]{750,1080},1,4));
        assertEquals(700,StatusBarPlacement.resolve(700,84,0,1080,new int[]{850,1080},1,4));
    }
    @Test public void avoidsClockNotificationAreaAndCameraCutout() {
        assertEquals(574,StatusBarPlacement.resolve(500,84,0,1080,new int[]{0,480,510,570,750,1080},3,4));
    }
    @Test public void respectsSafeInsetsAndClampsOutOfRangePreference() {
        assertEquals(320,StatusBarPlacement.resolve(999,80,10,400,new int[0],0,2));
        assertEquals(10,StatusBarPlacement.resolve(-100,80,10,400,new int[0],0,2));
    }
    @Test public void noSpaceHidesInsteadOfOverlappingAndRestoresWhenSpaceReturns() {
        assertEquals(-1,StatusBarPlacement.resolve(470,40,0,1080,new int[]{0,480,500,1080},2,2));
        assertEquals(482,StatusBarPlacement.resolve(470,40,0,1080,new int[]{0,480,600,1080},2,2));
    }
    @Test public void tracksIconMovementWithoutChangingPreference() {
        assertEquals(692,StatusBarPlacement.resolve(700,84,0,1080,new int[]{780,1080},1,4));
        assertEquals(722,StatusBarPlacement.resolve(700,84,0,1080,new int[]{600,718},1,4));
    }
    @Test public void invalidOrZeroWidthCannotPlace() {
        assertEquals(-1,StatusBarPlacement.resolve(100,200,0,100,new int[0],0,2));
        assertEquals(-1,StatusBarPlacement.resolve(100,0,0,1080,new int[0],0,2));
    }
}
