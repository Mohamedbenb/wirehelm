package com.nodecockpit.customization;
/** Manual opaque greyscale text; -1 keeps the existing default colour. */
final class TextTone {
 static boolean valid(int value){return value>=-1&&value<=100;}
 static int color(int value){int c=Math.round(Math.max(0,Math.min(100,value))*255f/100f);return 0xff000000|(c<<16)|(c<<8)|c;}
}
