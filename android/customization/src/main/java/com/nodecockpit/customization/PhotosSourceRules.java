package com.nodecockpit.customization;

import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

final class PhotosSourceRules {
    static final String CAMERA = "Camera";
    static final String VIDEOS = "Videos";
    static final String UNSORTED = "Unsorted";
    static final String DEVELOPMENT = "Development";
    private static final String SCREENSHOTS = "Screenshots";
    private static final Map<String, String> APPS = Map.ofEntries(
            Map.entry("com.facebook.katana", "Facebook"), Map.entry("com.facebook.orca", "Messenger"),
            Map.entry("com.android.chrome", "Chrome"), Map.entry("com.chrome.beta", "Chrome Beta"),
            Map.entry("com.instaprime.android", "Instagram"), Map.entry("com.instagram.android", "Instagram"),
            Map.entry("com.whatsapp", "WhatsApp"), Map.entry("com.openai.chatgpt", "ChatGPT"),
            Map.entry("com.giphy.messenger", "GIPHY"), Map.entry("org.forkclient.messenger.beta", "Fork Client"),
            Map.entry("org.forkgram.messenger", "Forkgram"), Map.entry("org.mozilla.firefox", "Firefox"),
            Map.entry("com.zhiliaoapp.musically", "TikTok"));
    private static final Pattern SCREEN_CAPTURE = Pattern.compile(
            "^(screenshot|screen[_ -]?shot|screen[_ -]?record(?:ing)?)[-_ .0-9].*");
    private static final Pattern WHATSAPP = Pattern.compile(
            "^(?:img-[0-9]{8}-wa[0-9]+(?:[ ._(-].*)?|whatsapp[_ -]image[_ -].*)$");
    private static final Pattern FACEBOOK = Pattern.compile("^fb_img_[0-9]+.*");
    private static final Pattern DEVELOPMENT_FILE = Pattern.compile(
            "^(?:node-[a-z0-9_-]+|termux-[a-z0-9_-]+|terminal[0-9]+|customization)\\.png$");

    record Source(String group, String model) {}
    record Evidence(int rank, Source source) {}
    record FilenameRules(boolean messenger, boolean facebook, boolean whatsapp) {
        static final FilenameRules DEFAULT = new FilenameRules(true, true, true);
    }

    static Evidence identify(boolean video, String owner, String filename, CloudCameraOrigin.Camera camera) {
        return identify(video, owner, filename, camera, FilenameRules.DEFAULT);
    }

    static Evidence identify(boolean video, String owner, String filename, CloudCameraOrigin.Camera camera,
                             FilenameRules rules) {
        String pkg = normalize(owner);
        String name = normalize(filename);
        String model = cameraLabel(camera);
        if (video) {
            return model.isEmpty() ? evidence(0, VIDEOS, "") : evidence(3, CAMERA, model);
        }
        if (rules.messenger() && name.contains("messenger_creation")) return evidence(4, "Messenger", "");
        String app = APPS.get(pkg);
        if (app != null) return evidence(3, app, "");
        if (pkg.equals("com.sec.android.app.camera") || pkg.equals("com.google.android.googlecamera")) {
            return evidence(3, CAMERA, model.isEmpty() ? "Model unknown" : model);
        }
        boolean screenshot = SCREEN_CAPTURE.matcher(name).matches();
        if (screenshot && pkg.equals("com.android.systemui")) return evidence(3, SCREENSHOTS, "");
        if (rules.facebook() && FACEBOOK.matcher(name).matches()) return evidence(2, "Facebook", "");
        if (rules.whatsapp() && WHATSAPP.matcher(name).matches()) return evidence(2, "WhatsApp", "");
        if (screenshot) return evidence(2, SCREENSHOTS, "");
        if (!model.isEmpty()) return evidence(2, CAMERA, model);
        if (pkg.equals("com.android.shell") && DEVELOPMENT_FILE.matcher(name).matches()) {
            return evidence(1, DEVELOPMENT, "");
        }
        return evidence(0, UNSORTED, "");
    }

    private static Evidence evidence(int rank, String group, String model) {
        return new Evidence(rank, new Source(group, model));
    }

    private static String cameraLabel(CloudCameraOrigin.Camera camera) {
        if (camera == null) return "";
        String label = camera.label();
        if (!label.matches("[a-z0-9][a-z0-9 ._+()/-]{1,89}")) return "";
        return switch (label) {
            case "xiaomi 23053rn02a", "xiaomi redmi 12" -> "Redmi 12";
            case "samsung sm-a366b", "samsung galaxy a36 5g" -> "Galaxy A36 5G";
            case "google pixel 10" -> "Pixel 10";
            case "phase one p 20" -> "Phase One P20";
            default -> label;
        };
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }
}
