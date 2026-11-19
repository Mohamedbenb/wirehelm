package com.example.remote_control
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import org.junit.Test
import org.junit.Assert.*
class SleepAwareMessengerTest {
 private class Fake: BinaryMessenger {
  var handler: BinaryMessenger.BinaryMessageHandler? = null
  override fun send(c: String, m: ByteBuffer?) {}
  override fun send(c: String, m: ByteBuffer?, r: BinaryMessenger.BinaryReply?) {}
  override fun setMessageHandler(c: String, h: BinaryMessenger.BinaryMessageHandler?) { handler=h }
  override fun setMessageHandler(c: String, h: BinaryMessenger.BinaryMessageHandler?, q: BinaryMessenger.TaskQueue?) { handler=h }
 }
 @Test fun asynchronousNativeWorkIsProtectedUntilReply() {
  val f=Fake(); var active=0; var reply: BinaryMessenger.BinaryReply?=null
  val tracked=SleepAwareMessenger(f,{active++;7L},{assertEquals(7L,it);active--})
  tracked.setMessageHandler("operation",{ _, r -> reply=r })
  f.handler!!.onMessage(null) {};assertEquals(1,active)
  reply!!.reply(null);assertEquals(0,active)
 }
 @Test fun synchronousFailureReleasesProtection() {
  val f=Fake();var active=0
  val tracked=SleepAwareMessenger(f,{active++;1L},{active--})
  tracked.setMessageHandler("operation",{ _, _ -> throw IllegalStateException() },null)
  try { f.handler!!.onMessage(null) {};fail() } catch (_: IllegalStateException) {}
  assertEquals(0,active)
 }
 @Test fun handlerRemovalIsForwarded() {
  val f=Fake();val tracked=SleepAwareMessenger(f,{1L},{})
  tracked.setMessageHandler("operation",null);assertNull(f.handler)
 }
}
