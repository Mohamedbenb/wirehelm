package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class ProcessWorkTest {
 @Test public void nestedRequestsRemainProtectedUntilBothFinish(){var a=ProcessWork.begin("provider");var b=ProcessWork.begin("root");try{assertEquals(2,ProcessWork.reasons().size());a.close();assertEquals(1,ProcessWork.reasons().size());}finally{a.close();b.close();}assertTrue(ProcessWork.reasons().isEmpty());}
 @Test public void exceptionAndRepeatedCloseDoNotLeakOrDoubleRelease(){try{try(var work=ProcessWork.begin("request")){throw new IllegalStateException();}}catch(IllegalStateException expected){}assertTrue(ProcessWork.reasons().isEmpty());var token=ProcessWork.begin("one");token.close();token.close();assertTrue(ProcessWork.reasons().isEmpty());}
 @Test public void completionNotifiesShutdownRecheck(){int[] changes={0};ProcessWork.onChanged(()->changes[0]++);try{var token=ProcessWork.begin("job");token.close();token.close();assertEquals(1,changes[0]);}finally{ProcessWork.onChanged(()->{});}}
}
