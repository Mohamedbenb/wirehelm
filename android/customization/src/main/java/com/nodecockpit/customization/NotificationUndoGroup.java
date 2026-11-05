package com.nodecockpit.customization;

import java.util.*;

/** Identity snapshot of a native group. A changing group ends the grace, without cancellation. */
final class NotificationUndoGroup {
    static final class Member {
        final String key;
        final Object entry,generation,row;
        final int state;
        Member(String key,Object entry,Object generation){this(key,entry,generation,null,0);}
        Member(String key,Object entry,Object generation,Object row,int state){this.key=Objects.requireNonNull(key);this.entry=Objects.requireNonNull(entry);this.generation=Objects.requireNonNull(generation);this.row=row;this.state=state;}
    }
    private final Map<String,Member> members=new HashMap<>();
    NotificationUndoGroup(List<Member> originals){
        if(originals.isEmpty())throw new IllegalArgumentException("Empty notification group");
        for(Member member:originals)if(members.put(member.key,member)!=null)throw new IllegalArgumentException("Duplicate notification key");
    }
    boolean matches(List<Member> current){
        if(current.size()!=members.size())return false;
        Set<String> seen=new HashSet<>();
        for(Member member:current){
            Member original=members.get(member.key);
            if(!seen.add(member.key)||original==null||original.entry!=member.entry||original.generation!=member.generation||original.row!=member.row||original.state!=member.state)return false;
        }
        return true;
    }
}
