package com.nodecockpit.customization;
/** -1 retains automatic timing; explicit values are finite transition durations in milliseconds. */
final class TextAdaptationDuration {
    static final int AUTO=-1,MAX=10000;
    static boolean valid(int value){return value>=AUTO&&value<=MAX;}
}
