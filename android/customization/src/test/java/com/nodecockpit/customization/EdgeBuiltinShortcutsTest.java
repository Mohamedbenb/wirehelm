package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class EdgeBuiltinShortcutsTest {
 @Test public void quickAddPreservesExistingFoldersAndDoesNotDuplicate(){String before="com.example.one+com.example.two,com.example.three";String added=EdgeBuiltinShortcuts.addClipboard(before);assertEquals(before+","+EdgeBuiltinShortcuts.CLIPBOARD,added);assertEquals(added,EdgeBuiltinShortcuts.addClipboard(added));String inFolder="com.example.one+"+EdgeBuiltinShortcuts.CLIPBOARD;assertEquals(inFolder,EdgeBuiltinShortcuts.addClipboard(inFolder));}
 @Test public void fullFavoritesAreNotSilentlyTruncated(){StringBuilder full=new StringBuilder();for(int i=0;i<12;i++){if(i>0)full.append(',');full.append("com.example.app").append(i);}try{EdgeBuiltinShortcuts.addClipboard(full.toString());fail();}catch(IllegalArgumentException expected){} }
 @Test public void onlyKnownDestinationsOpenFeatureRoutes(){assertEquals("/clipboard-shelf",EdgeBuiltinShortcuts.route("clipboard"));assertEquals("/edge-actions",EdgeBuiltinShortcuts.route("edge-actions"));assertNull(EdgeBuiltinShortcuts.route("arbitrary"));assertNull(EdgeBuiltinShortcuts.route(null));assertTrue(FeaturePolicy.validEdgeApps(EdgeBuiltinShortcuts.CLIPBOARD));}
}
