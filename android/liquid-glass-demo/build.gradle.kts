plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
 namespace = "com.nodecockpit.glassdemo"
 compileSdk = 37
 defaultConfig { applicationId = "com.nodecockpit.glassdemo"; minSdk = 33; targetSdk = 37; versionCode = 12; versionName = "1.5.2-dev" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies { implementation(project(":liquid-glass-engine")) }
