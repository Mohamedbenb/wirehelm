package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class GlassBackdropBlurTest {
 @Test public void coversOddSizedInputs(){assertEquals(26,GlassBackdropBlur.reducedSize(101));assertEquals(25,GlassBackdropBlur.reducedSize(100));assertEquals(1,GlassBackdropBlur.reducedSize(1));}
 @Test public void emptySizeCannotAllocateZero(){assertEquals(1,GlassBackdropBlur.reducedSize(0));assertEquals(1,GlassBackdropBlur.reducedSize(-1));}
}
