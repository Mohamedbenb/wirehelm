package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassContrastTest {
    @Test public void transparentGlassFollowsBackdrop() {
        assertEquals(GlassContrast.DARK,GlassContrast.foreground(0,.95f,0));
        assertEquals(GlassContrast.LIGHT,GlassContrast.foreground(0,.05f,0));
    }
    @Test public void translucentTintDoesNotDictateTextColor() {
        assertEquals(GlassContrast.DARK,GlassContrast.foreground(0x64181d24,.95f,0));
        assertEquals(GlassContrast.LIGHT,GlassContrast.foreground(0x48f2f7fb,.05f,0));
    }
    @Test public void compactIconsUseTheDrawnTileNotAnUnusedIconPill() {
        assertEquals(GlassContrast.LIGHT,GlassContrast.foreground(0x8c000000,.96f,0));
        assertEquals(GlassContrast.DARK,GlassContrast.foreground(0,.96f,0));
    }
    @Test public void OpaqueTintDominatesBackdrop() {
        assertEquals(GlassContrast.LIGHT,GlassContrast.foreground(0xff181d24,1f,GlassContrast.DARK));
        assertEquals(GlassContrast.DARK,GlassContrast.foreground(0xfff2f7fb,0f,GlassContrast.LIGHT));
    }
    @Test public void mixedBackgroundsAlwaysHaveProtectedEndpointContrast() {
        for(int tint:new int[]{0,0x48f2f7fb,0x64181d24,0x88ff0066,0xa000cc99}) for(int ink:new int[]{GlassContrast.DARK,GlassContrast.LIGHT}) for(double guard:new double[]{3,4.5,7}) {
            int protectedTint=GlassContrast.protect(tint,ink,guard);
            assertTrue(GlassContrast.worstContrast(ink,protectedTint)>=guard);
            for(int step=0;step<=100;step++) assertTrue(GlassContrast.contrast(ink,protectedTint,step/100f)>=guard);
            assertTrue((protectedTint>>>24)>=(tint>>>24));
        }
    }
    @Test public void adequateBackingIsUnchangedAndProtectionIsIdempotent() {
        assertEquals(0xccffffff,GlassContrast.protect(0xccffffff,GlassContrast.DARK,4.5));
        int p=GlassContrast.protect(0x18cc99aa,GlassContrast.LIGHT,4.5);
        assertEquals(p,GlassContrast.protect(p,GlassContrast.LIGHT,4.5));
        assertTrue((p>>>24)<255);
    }
    @Test public void childGlassReusesDrawerProtectionWithoutBecomingOpaque() {
        int base=GlassContrast.protect(0x3d222831,GlassContrast.DARK,4.5);
        int child=GlassContrast.protect(0x20eeeeee,GlassContrast.DARK,4.5,base);
        assertEquals(0x20eeeeee,child);
        assertTrue(GlassContrast.worstContrast(GlassContrast.DARK,GlassContrast.composite(child,base))>=4.5);
    }
}
