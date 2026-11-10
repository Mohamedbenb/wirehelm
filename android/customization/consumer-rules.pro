# The framework loads this class by name from META-INF/xposed/java_init.list.
-keep class com.nodecockpit.customization.NetworkSpeedModule { *; }
-keep class com.nodecockpit.customization.NetworkSpeedModule$* { *; }
-keep class com.nodecockpit.customization.PhotosCloudCameraModule { *; }
-keep class com.nodecockpit.customization.PhotosCloudCameraModule$* { *; }
-dontwarn io.github.libxposed.api.**
-dontwarn io.github.libxposed.annotation.**
