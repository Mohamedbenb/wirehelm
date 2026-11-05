package com.termux.terminal;
import org.junit.Test;
import static org.junit.Assert.*;
public class WindowsResizeTest {
    private TerminalBuffer filled(boolean windows) {
        TerminalBuffer b = new TerminalBuffer(10, 200, 27);
        b.preserveHistoryOnExpansion = windows;
        for (int i = 1; i <= 100; i++) {
            String line = String.valueOf(i);
            for (int x = 0; x < line.length(); x++) b.setChar(x, 26, line.charAt(x), TextStyle.NORMAL);
            b.scrollDownOneLine(0, 27, TextStyle.NORMAL);
        }
        return b;
    }
    @Test public void windowsHistorySurvivesExpansionAndRepaint() {
        TerminalBuffer b = filled(true);
        int history = b.getActiveTranscriptRows();
        int[] cursor = {0, 26};
        b.resize(10, 50, 200, cursor, TextStyle.NORMAL, false);
        assertEquals(history, b.getActiveTranscriptRows());
        assertEquals(26, cursor[1]);
        // A ConPTY repaint can erase the viewport without erasing rescued history.
        b.blockSet(0, 0, 10, 50, ' ', TextStyle.NORMAL);
        String text = b.getTranscriptText();
        assertTrue(text.contains("52\n53"));
        assertTrue(text.contains("73\n74"));
    }
    @Test public void linuxExpansionStillPullsHistoryIntoScreen() {
        TerminalBuffer b = filled(false);
        int history = b.getActiveTranscriptRows();
        int[] cursor = {0, 26};
        b.resize(10, 50, 200, cursor, TextStyle.NORMAL, false);
        assertEquals(history - 23, b.getActiveTranscriptRows());
        assertEquals(49, cursor[1]);
    }
}
