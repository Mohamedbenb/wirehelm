package com.nodecockpit.customization;
import org.junit.Test;
import static org.junit.Assert.*;
public class EdgeActionSettingsTest {
 @Test public void defaultsRetainExistingButtons(){EdgeActionSettings s=EdgeActionSettings.safe("{}");assertEquals(5,s.order.size());assertTrue(s.hidden.contains("clipboard"));assertTrue(s.labels);assertEquals(24,s.iconSize);}
 @Test public void customLayoutAndAllHiddenAreValid()throws Exception{EdgeActionSettings s=new EdgeActionSettings("{\"order\":[\"clipboard\",\"edit\",\"settings\",\"windows\",\"capture\"],\"hidden\":[\"edit\",\"windows\",\"capture\",\"clipboard\",\"settings\"],\"labels\":false,\"iconSize\":32,\"columns\":1}");assertEquals("clipboard",s.order.get(0));assertEquals(5,s.hidden.size());assertFalse(s.labels);}
 @Test public void invalidDuplicatesUnknownActionsAndSizesAreRejected(){for(String raw:new String[]{"{\"order\":[\"edit\",\"edit\",\"settings\",\"windows\",\"capture\"]}","{\"hidden\":[\"unknown\"]}","{\"iconSize\":99}","{\"columns\":5}","{\"labels\":\"false\"}"}){try{new EdgeActionSettings(raw);fail(raw);}catch(Exception expected){}}}
 @Test public void narrowPanelsKeepTouchTargetsAndFooterSpace()throws Exception{EdgeActionSettings s=new EdgeActionSettings("{\"columns\":4}");assertEquals(1,s.columnsFor(66,true));assertEquals(4,s.columnsFor(206,true));assertEquals(96,EdgeActionSettings.toolbarHeightLimit(240));assertEquals(260,EdgeActionSettings.toolbarHeightLimit(520));}
 @Test public void clippedCardDoesNotSubtractItsOverhangTwice()throws Exception{EdgeActionSettings s=new EdgeActionSettings("{\"columns\":4}");assertEquals(116,EdgeActionSettings.contentWidth(140,12));assertEquals(2,s.columnsFor(EdgeActionSettings.contentWidth(140,12),false));assertEquals(4,s.columnsFor(EdgeActionSettings.contentWidth(216,12),false));assertEquals(48,EdgeActionSettings.contentWidth(60,12));}
 @Test public void toolbarIsOwnedByEdgeSetupScope(){assertTrue(SavedSetupScope.owns("edge","edgePanelActions"));assertFalse(SavedSetupScope.owns("glass","edgePanelActions"));}
}
