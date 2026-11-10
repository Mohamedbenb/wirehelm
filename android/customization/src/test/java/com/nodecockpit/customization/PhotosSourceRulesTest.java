package com.nodecockpit.customization;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class PhotosSourceRulesTest {
    @Test public void explicitMessengerNameAndKnownPhotoSources() {
        assertEquals("Messenger", group(false, "com.android.providers.downloads.ui", "Messenger_creation_A.jpg"));
        assertEquals("WhatsApp", group(false, "com.android.providers.downloads.ui", "whatsapp_image_2024.jpeg"));
        assertEquals("Facebook", group(false, "com.google.android.apps.restore", "FB_IMG_123.jpg"));
        assertEquals("Unsorted", group(false, "com.google.android.apps.restore", "IMG_123.jpg"));
    }

    @Test public void onlyVideosWithCameraMetadataGoToCamera() {
        assertEquals("Videos", group(true, "com.whatsapp", "VID-20260101-WA123.mp4"));
        assertEquals("Videos", group(true, "com.sec.android.app.camera", "VID_20260101.mp4"));
        var camera = new CloudCameraOrigin.Camera("xiaomi", "23053rn02a");
        assertEquals(new PhotosSourceRules.Source("Camera", "Redmi 12"),
                PhotosSourceRules.identify(true, "com.google.android.apps.restore", "VID.mp4", camera).source());
        assertEquals("Unsorted", group(false, "", "VID_20240830_031914.jpg"));
    }

    @Test public void disablingFilenameRulesKeepsRecordedSources() {
        var disabled = new PhotosSourceRules.FilenameRules(false, false, false);
        assertEquals("WhatsApp", PhotosSourceRules.identify(false, "com.whatsapp",
                "Messenger_creation_A.jpg", null, disabled).source().group());
        for (String filename : new String[]{"Messenger_creation_A.jpg", "FB_IMG_123.jpg", "IMG-20260101-WA0001.jpg"}) {
            assertEquals("Unsorted", PhotosSourceRules.identify(false, "", filename, null, disabled).source().group());
        }
    }

    @Test public void developmentRequiresShellAndMatchingPng() {
        assertEquals("Development", group(false, "com.android.shell", "node-final101.png"));
        assertEquals("Unsorted", group(false, "", "node-final101.png"));
    }

    private static String group(boolean video, String owner, String filename) {
        return PhotosSourceRules.identify(video, owner, filename, null).source().group();
    }
}
