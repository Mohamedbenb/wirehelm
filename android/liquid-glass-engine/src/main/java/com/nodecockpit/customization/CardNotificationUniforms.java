package com.nodecockpit.customization;
import java.nio.*;import java.util.Arrays;
final class CardNotificationUniforms {
 static final int BYTES=848,MAX_SHAPES=13,MAX_BUTTONS=10,BUTTON_OFFSET=688;
 static byte[] normal(byte[] source){if(source.length!=272)throw new IllegalArgumentException("Invalid base ABI");return Arrays.copyOf(source,BYTES);}
 static byte[] cluster(byte[] base,float[][] shapes,float blur,float mix){return cluster(base,shapes,new float[0][],blur,mix);}
 static byte[] cluster(byte[] base,float[][] shapes,float[][] buttons,float blur,float mix){return cluster(base,shapes,buttons,blur,mix,30);}
 static byte[] cluster(byte[] base,float[][] shapes,float[][] buttons,float blur,float mix,float pillStrength){if(shapes.length>MAX_SHAPES||buttons.length>MAX_BUTTONS)throw new IllegalArgumentException("Too many regions");byte[] out=normal(CardMergeUniforms.extend(base,null));ByteBuffer b=ByteBuffer.wrap(out).order(ByteOrder.nativeOrder());b.putFloat(248,1);b.putFloat(256,buttons.length);float strength=Math.max(0,Math.min(100,pillStrength));float t=Math.min(1,strength/10);b.putFloat(252,t*t*(3-2*t));b.putFloat(260,Math.max(blur,.48f*strength));b.putFloat(264,blur);b.putFloat(268,mix);for(int i=0;i<shapes.length;i++){float[] s=shapes[i];if(s.length!=8)throw new IllegalArgumentException("Invalid region");for(int k=0;k<8;k++){if(!Float.isFinite(s[k]))throw new IllegalArgumentException("Non-finite region");b.putFloat(272+i*32+k*4,s[k]);}}for(int i=0;i<buttons.length;i++){if(buttons[i].length!=4)throw new IllegalArgumentException("Invalid control");for(int k=0;k<4;k++){if(!Float.isFinite(buttons[i][k]))throw new IllegalArgumentException("Non-finite control");b.putFloat(BUTTON_OFFSET+i*16+k*4,buttons[i][k]);}}return out;}
}
