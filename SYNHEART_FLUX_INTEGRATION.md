# Synheart Flux Integration

This document explains how to integrate synheart-flux (Rust library) with synheart-behavior-dart for HSI-compliant behavioral metrics computation.

## Required Version

For behavior metrics, use **synheart-flux 0.2.0** or later. Download artifacts from the [v0.2.0 release](https://github.com/synheart-ai/synheart-flux/releases/tag/v0.2.0) (or the [releases page](https://github.com/synheart-ai/synheart-flux/releases)).

**Using the released Flux (not building from source):** This SDK repo may bundle pre-built Flux binaries for convenience; those are not guaranteed to be 0.2.0. To use the **released** Flux 0.2.0:

1. **Android**: From the [v0.2.0 release](https://github.com/synheart-ai/synheart-flux/releases/tag/v0.2.0), download `synheart-flux-android-jniLibs.tar.gz`, extract it, and **replace** the contents of `android/src/main/jniLibs/` with the extracted `.so` files (arm64-v8a, armeabi-v7a, x86_64).
2. **iOS**: From the same release, download `synheart-flux-ios-xcframework.zip`, extract it, and **replace** `ios/Frameworks/SynheartFlux.xcframework` with the extracted XCFramework.

After replacing, you are using the official Flux 0.2.0 release for behavior.

## Overview

The synheart-behavior SDK **requires** synheart-flux for computing behavioral metrics. All behavioral and typing metric calculations are performed by the Rust library, ensuring:
- HSI compliance
- Cross-platform consistency (same Rust code on iOS and Android)
- Baseline support across sessions
- Deterministic, reproducible results

The SDK uses synheart-flux for computing:
- Distraction score
- Focus hint
- Burstiness (Barabási formula)
- Task switch rate
- Notification load
- Scroll jitter rate
- Deep focus blocks
- Interaction intensity
- Typing session metrics (typing session count, average keystrokes, typing speed, etc.)
- And all other HSI-compliant metrics

**Note**: synheart-flux is **required**. If the library is not available, session ending will fail with an error.

## Benefits

- **HSI Compliance**: Metrics computed using synheart-flux are fully HSI-compliant
- **Cross-Platform Consistency**: Same Rust code runs on iOS and Android
- **Baseline Support**: Rolling baselines across sessions
- **Deterministic Output**: Reproducible results for research

## Installation

### Android

1. Download the synheart-flux Android libraries from the [synheart-flux v0.2.0 release](https://github.com/synheart-ai/synheart-flux/releases/tag/v0.2.0) (or latest):
   - `synheart-flux-android-jniLibs.tar.gz`

2. Extract and place the `.so` files:
   ```
   android/src/main/jniLibs/
   ├── arm64-v8a/
   │   └── libsynheart_flux.so
   ├── armeabi-v7a/
   │   └── libsynheart_flux.so
   └── x86_64/
       └── libsynheart_flux.so
   ```

3. The SDK will automatically detect and use the library.

### iOS

1. Download the synheart-flux iOS XCFramework from the [synheart-flux v0.2.0 release](https://github.com/synheart-ai/synheart-flux/releases/tag/v0.2.0) (or latest):
   - `synheart-flux-ios-xcframework.zip`

2. Extract and place the XCFramework:
   ```
   ios/Frameworks/
   └── SynheartFlux.xcframework/
       ├── ios-arm64/
       ├── ios-arm64_x86_64-simulator/
       └── Info.plist
   ```

3. Run `pod install` in your iOS project.

### Flutter

For Flutter, include both Android and iOS libraries as described above. The Dart FFI bridge will automatically load the appropriate library for each platform.

## Building from Source

If you prefer to build synheart-flux from source:

### Android
```bash
cd /path/to/synheart-flux
ANDROID_NDK_HOME=/path/to/ndk bash scripts/build-android.sh dist/android/jniLibs
# Copy dist/android/jniLibs/* to android/src/main/jniLibs/
```

### iOS
```bash
cd /path/to/synheart-flux
bash scripts/build-ios-xcframework.sh dist/ios
# Copy dist/ios/SynheartFlux.xcframework to ios/Frameworks/
```

## Dart FFI Usage

The SDK includes a Dart FFI bridge for direct Rust calls:

```dart
import 'package:synheart_behavior/synheart_behavior.dart';

// Initialize the bridge
final bridge = FluxBridge.instance;
if (bridge.initialize()) {
  print('Rust library loaded successfully');
}

// One-shot computation
final sessionJson = convertSessionToFluxJson(
  sessionId: 'session-123',
  deviceId: 'device-456',
  timezone: 'America/New_York',
  startTime: sessionStart,
  endTime: sessionEnd,
  events: eventsList,
);

final hsiJson = bridge.behaviorToHsi(sessionJson);
final metrics = bridge.parseHsiJson(hsiJson);

// Stateful processor with baselines
final processor = FluxBehaviorProcessor(baselineWindowSessions: 20);

// Load previous baselines
if (savedBaselines != null) {
  processor.loadBaselines(savedBaselines);
}

// Process session
final hsi = processor.process(sessionJson);

// Save baselines for next time
final baselines = processor.saveBaselines();
await storage.save('baselines', baselines);

// Clean up
processor.dispose();
```

## Verifying Integration

To verify synheart-flux is being used:

### Android
Check logcat for:
```
D/BehaviorSDK: Successfully computed metrics using synheart-flux
```

### iOS
Check console for:
```
BehaviorSDK: Successfully computed metrics using synheart-flux
```

If you see "Flux is required but metrics are not available" errors, the Rust library is not loaded correctly and the SDK will fail.

## Verifying Flux version

To confirm you have the **updated** Flux (e.g. 0.2.0):

### At runtime (easiest)

- **Android**: After launching the app, check **logcat** (filter by `FluxBridge` or `FluxJniBridge`). You should see:
  ```
  D/FluxBridge: synheart-flux version: 0.2.0
  ```
  or from the JNI bridge:
  ```
  I/FluxJniBridge: synheart-flux version: 0.2.0
  ```
- **iOS**: In the Xcode or device console, look for:
  ```
  FluxBridge: ✅ Found synheart-flux version: 0.2.0
  ```

If you see `0.2.0` (or higher), you are using the updated Flux release.

### From code (Android)

You can also read the version in app code:
```kotlin
val version = FluxBridge.getFluxVersion()  // e.g. "0.2.0" or null
```

### From HSI output

The HSI JSON returned by Flux includes the producer version. After processing a session, inspect the payload:
```json
"producer": { "name": "synheart-flux", "version": "0.2.0", ... }
```
If `producer.version` is `"0.2.0"`, the loaded library is the 0.2.0 release.

## Required Integration

**synheart-flux is mandatory** for the SDK to function. The SDK will fail to end sessions if Flux is not available. This ensures:
- Consistent HSI-compliant metrics across all platforms
- No fallback to legacy native implementations
- Guaranteed cross-platform metric consistency

## Troubleshooting

### Android: Library not loading
- Verify the `.so` files are in the correct ABI folders
- Check that the app has the correct ABI filter in build.gradle
- Try adding `android:extractNativeLibs="true"` to AndroidManifest.xml

### iOS: Symbols not found
- Ensure the XCFramework is properly linked
- Run `pod install --repo-update`
- Check that OTHER_LDFLAGS includes `-lsynheart_flux`

### Dart FFI: Library not found
- Verify the native libraries are bundled in the app
- Check platform-specific library loading paths
- Ensure FFI is enabled in the app's configuration
