package com.nodecockpit.customization;
import java.nio.*;import java.util.Arrays;
/** Sixteen native tile outlines; per-corner radii and alpha, no per-frame pixels. */
final class NativeQsUniforms {
 static final int MAX=16,BYTES=1392;
 static byte[] pack(byte[] base,float[][] shapes,float blur,float mix){return pack(base,shapes,blur,mix,null);}
 static byte[] pack(byte[] base,float[][] shapes,float blur,float mix,float[] progress){return pack(base,shapes,blur,mix,progress,null);}
 static byte[] pack(byte[] base,float[][] shapes,float blur,float mix,float[] progress,float[] indicator){if(shapes.length>MAX)throw new IllegalArgumentException("QS region limit");byte[] out=Arrays.copyOf(CardMergeUniforms.extend(base,null),BYTES);ByteBuffer b=ByteBuffer.wrap(out).order(ByteOrder.nativeOrder());b.putFloat(248,1);b.putFloat(264,blur);b.putFloat(268,mix);for(int i=0;i<shapes.length;i++){if(shapes[i].length!=16)throw new IllegalArgumentException("QS shape ABI");for(int k=0;k<16;k++){float v=shapes[i][k];if(!Float.isFinite(v))throw new IllegalArgumentException("QS finite geometry");b.putFloat(272+i*64+k*4,v);}}if(progress!=null){if(progress.length!=12)throw new IllegalArgumentException("Progress mask ABI");for(int i=0;i<12;i++){if(!Float.isFinite(progress[i]))throw new IllegalArgumentException("Progress finite geometry");b.putFloat(1296+i*4,progress[i]);}}if(indicator!=null){if(indicator.length!=12)throw new IllegalArgumentException("Indicator mask ABI");for(int i=0;i<12;i++){if(!Float.isFinite(indicator[i]))throw new IllegalArgumentException("Indicator finite geometry");b.putFloat(1344+i*4,indicator[i]);}}return out;}
}
