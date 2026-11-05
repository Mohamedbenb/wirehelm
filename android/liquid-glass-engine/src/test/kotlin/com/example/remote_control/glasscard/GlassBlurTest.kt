package com.example.remote_control.glasscard
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.sqrt
class GlassBlurTest {
 @Test fun endpointsAndInvalidValues(){assertEquals(0f,GlassBlur.radius(0f),0f);assertEquals(0f,GlassBlur.contribution(0f),0f);assertEquals(48f,GlassBlur.radius(100f),0f);assertEquals(1f,GlassBlur.contribution(100f),0f);assertEquals(0f,GlassBlur.radius(Float.NaN),0f);assertEquals(48f,GlassBlur.radius(200f),0f)}
 @Test fun monotonicAndBounded(){var oldR=0f;var oldM=0f;for(i in 0..1000){val s=i/10f;val r=GlassBlur.radius(s);val m=GlassBlur.contribution(s);assertTrue(r>=oldR&&r<=48);assertTrue(m>=oldM&&m<=1);oldR=r;oldM=m}}
 @Test fun legacyVariancePreserved(){for(r in listOf(0f,1f,12f,48f))for(m in listOf(0f,.2f,1f))for(clear in listOf(false,true)){val expected=r*(if(clear).35f else 1f)*sqrt(m);val s=GlassBlur.fromLegacy(r,m,clear);assertEquals(expected,GlassBlur.radius(s)*sqrt(GlassBlur.contribution(s)),.001f)}}
}
