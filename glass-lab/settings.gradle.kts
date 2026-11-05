pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
plugins {
 id("com.android.application") version "9.1.0" apply false
 id("com.android.library") version "9.1.0" apply false
 id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name="LiquidGlassLab"
include(":liquid-glass-engine",":liquid-glass-demo")
project(":liquid-glass-engine").projectDir=file("../android/liquid-glass-engine")
project(":liquid-glass-demo").projectDir=file("../android/liquid-glass-demo")
