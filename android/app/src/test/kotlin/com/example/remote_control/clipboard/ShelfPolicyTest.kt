package com.example.remote_control.clipboard
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class ShelfPolicyTest {
 @Test fun captureIsOptInAndNeverIncludesLockedOrSensitiveClips(){
  assertFalse(ShelfPolicy().accepts("com.example.app",false,true))
  val p=ShelfPolicy(enabled=true)
  assertTrue(p.accepts("com.example.app",false,true))
  assertFalse(p.accepts("com.example.app",true,true))
  assertFalse(p.accepts("com.example.app",false,false))
 }
 @Test fun exclusionsUnknownSourcesAndSelfCopiesAreRejected(){
  val p=ShelfPolicy(enabled=true,excluded=setOf("com.example.app"))
  for(source in listOf("com.example.app","","com.example.remote_control"))assertFalse(p.accepts(source,false,true))
  assertFalse(ShelfPolicy(enabled=true).accepts("com.x8bit.bitwarden",false,true))
 }
 @Test fun configurationRoundTripKeepsExplicitEmptyExclusions(){
  val p=ShelfPolicy(true,200,30,false,emptySet());assertEquals(p,ShelfPolicy.parse(p.json()))
 }
 @Test fun packageNamesAndRetentionAreBounded(){
  assertEquals(setOf("com.example.app"),ShelfPolicy.parse(JSONObject("""{"excluded":["com.example.app"]}""")).excluded)
  for(json in listOf("""{"limit":99999}""","""{"days":0}""","""{"excluded":["bad/path"]}""")){
   try{ShelfPolicy.parse(JSONObject(json));fail("Invalid options accepted")}catch(expected:IllegalArgumentException){}
  }
 }
}
