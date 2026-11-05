package com.nodecockpit.customization;
import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;
public class NotificationUndoGroupTest {
    private NotificationUndoGroup.Member m(String key){return new NotificationUndoGroup.Member(key,new Object(),new Object());}
    @Test public void reorderDoesNotInvalidate(){NotificationUndoGroup.Member a=m("child"),s=m("summary");assertTrue(new NotificationUndoGroup(Arrays.asList(a,s)).matches(Arrays.asList(s,a)));}
    @Test public void addedMessageInvalidatesBeforeSummaryCancellation(){NotificationUndoGroup.Member a=m("child"),s=m("summary");assertFalse(new NotificationUndoGroup(Arrays.asList(a,s)).matches(Arrays.asList(a,s,m("new"))));}
    @Test public void removedMessageInvalidates(){NotificationUndoGroup.Member a=m("child"),s=m("summary");assertFalse(new NotificationUndoGroup(Arrays.asList(a,s)).matches(Arrays.asList(s)));}
    @Test public void updatedSummaryInvalidates(){NotificationUndoGroup.Member a=m("child"),s=m("summary");assertFalse(new NotificationUndoGroup(Arrays.asList(a,s)).matches(Arrays.asList(a,new NotificationUndoGroup.Member(s.key,s.entry,new Object()))));}
    @Test public void updatedSiblingInvalidates(){NotificationUndoGroup.Member a=m("child"),b=m("sibling");assertFalse(new NotificationUndoGroup(Arrays.asList(a,b)).matches(Arrays.asList(a,new NotificationUndoGroup.Member(b.key,b.entry,new Object()))));}
    @Test public void reusedKeyCannotMatch(){NotificationUndoGroup.Member a=m("child");assertFalse(new NotificationUndoGroup(Arrays.asList(a)).matches(Arrays.asList(new NotificationUndoGroup.Member(a.key,new Object(),a.generation))));}
    @Test public void duplicateCannotStandInForMissingMember(){NotificationUndoGroup.Member a=m("child"),s=m("summary");assertFalse(new NotificationUndoGroup(Arrays.asList(a,s)).matches(Arrays.asList(a,a)));}
    @Test public void snapshotDoesNotRetainMutableList(){NotificationUndoGroup.Member a=m("child");List<NotificationUndoGroup.Member> list=new ArrayList<>(Arrays.asList(a));NotificationUndoGroup g=new NotificationUndoGroup(list);list.clear();assertTrue(g.matches(Arrays.asList(a)));}
    @Test public void childRowReplacementInvalidatesSummaryGrace(){Object entry=new Object(),generation=new Object();NotificationUndoGroup.Member a=new NotificationUndoGroup.Member("child",entry,generation,new Object(),1);assertFalse(new NotificationUndoGroup(Arrays.asList(a)).matches(Arrays.asList(new NotificationUndoGroup.Member("child",entry,generation,new Object(),1))));}
    @Test public void changedNativeChildPolicyInvalidatesSummaryGrace(){Object entry=new Object(),generation=new Object(),row=new Object();NotificationUndoGroup.Member a=new NotificationUndoGroup.Member("child",entry,generation,row,1);assertFalse(new NotificationUndoGroup(Arrays.asList(a)).matches(Arrays.asList(new NotificationUndoGroup.Member("child",entry,generation,row,2))));}
}
