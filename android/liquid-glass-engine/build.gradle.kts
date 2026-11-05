plugins { id("com.android.library"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.nodecockpit.glassengine"
    compileSdk = 37
    defaultConfig { minSdk = 26; consumerProguardFiles("consumer-rules.pro") }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    compileOnly(files("libs/card-platform-compile-only.jar"))
    testImplementation("junit:junit:4.13.2")
}
val syncCardShader by tasks.registering(Exec::class) {
    workingDir(projectDir)
    commandLine("python", "tools/sync_card_shader.py")
    inputs.file(file("tools/sync_card_shader.py"))
    inputs.files(fileTree("src/main/kotlin") { include("**/CardCompositorMaterial.kt", "**/GlassReaction.kt", "**/GlassTouchRipples.kt") })
    outputs.file(file("src/main/java/com/nodecockpit/customization/CardLiquidShader.java"))
}
val verifyEngineBoundary by tasks.registering(Exec::class) {
    dependsOn(syncCardShader)
    workingDir(projectDir)
    commandLine("python", "tools/verify_boundary.py")
    inputs.file(file("tools/verify_boundary.py"))
    inputs.dir(file("src/main"))
}
val verifyEngineCoverage by tasks.registering(Exec::class) {
    dependsOn(syncCardShader)
    workingDir(projectDir)
    commandLine("python", "tools/verify_coverage.py")
    inputs.dir(file("src/main"))
    inputs.file(file("coverage/inventory.json"))
    inputs.file(file("tools/verify_coverage.py"))
}
tasks.named("preBuild") { dependsOn(syncCardShader, verifyEngineBoundary, verifyEngineCoverage) }
