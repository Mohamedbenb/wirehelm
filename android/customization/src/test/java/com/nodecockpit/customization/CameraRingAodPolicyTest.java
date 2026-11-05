package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class CameraRingAodPolicyTest {
 @Test public void interactiveAlwaysHides(){for(int s=0;s<7;s++)assertFalse(CameraRingAodPolicy.canDraw(true,s,0));}
 @Test public void onlyDozeStatesCanDraw(){for(int s=0;s<7;s++)assertEquals(s==3||s==4,CameraRingAodPolicy.canDraw(false,s,0));}
 @Test public void fullyOffIsDark(){assertFalse(CameraRingAodPolicy.canDraw(false,1,0));}
 @Test public void unsupportedRotationHides(){for(int r:new int[]{-1,1,2,3})assertFalse(CameraRingAodPolicy.canDraw(false,3,r));}
}
