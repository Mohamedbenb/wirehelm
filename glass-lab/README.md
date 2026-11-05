# Independent Glass Engine build

This Gradle entry point includes only `liquid-glass-engine` and `liquid-glass-demo`. It does not include Flutter, the main app or the SystemUI adapter. Use the existing wrapper from the repository root:

```powershell
android/gradlew.bat -p glass-lab :liquid-glass-engine:testDebugUnitTest :liquid-glass-engine:assembleRelease :liquid-glass-demo:assembleDebug
```

See `../android/liquid-glass-engine/README.md` for SDK requirements, public APIs, lifecycle and limitations.

The1.5.1-dev lab adds Brightness → Open native brightness backend. This uses the same engine component as the current adapter source and exposes progress/indicator blur, native motion, hide/show and recreate/retry. Ordinary app restrictions can make framework backdrop blur unavailable; the preview then explicitly reports a solid fallback. The main sample's RenderEffect/shader modes remain separate studies. New native-backend visuals are not yet device validated.
