package com.example.remote_control.glasscard
import org.junit.Assert.*
import org.junit.Test
class ForegroundInkPolicyTest {
 @Test fun whiteHasBlackOutlineAndBlackHasWhiteOutline(){assertEquals(0xff000000.toInt(),ForegroundInkPolicy.outline(0xffffffff.toInt()));assertEquals(0xffffffff.toInt(),ForegroundInkPolicy.outline(0xff000000.toInt()));assertEquals(21.0,ForegroundInkPolicy.contrast(-1,0xff000000.toInt()),.0001)}
 @Test fun outlineChoosesAtLeastTheAlternativeContrastForColourGrid(){for(r in 0..255 step 17)for(g in 0..255 step 17)for(b in 0..255 step 17){val c=(0xff000000.toInt() or (r shl 16) or (g shl 8) or b);val selected=ForegroundInkPolicy.outline(c);val other=if(selected==-1)0xff000000.toInt() else -1;assertTrue(ForegroundInkPolicy.contrast(c,selected)>=ForegroundInkPolicy.contrast(c,other));assertTrue(ForegroundInkPolicy.contrast(c,selected)>=4.5)}}
}
