# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-02-06

### Added

- **Correction rate and clipboard activity rate**: Typing session summary now includes `correctionRate` and `clipboardActivityRate` computed by synheart-flux (Rust). The SDK sends per-session counts (backspace, copy, paste, cut) to Flux and receives the aggregated rates in the typing session summary.
- Per-typing-session counts: Typing events now include `number_of_backspace`, `number_of_copy`, `number_of_paste`, and `number_of_cut` (and `number_of_delete` as 0 on mobile). Flux uses these to compute correction rate and clipboard activity rate.
- Example app and Dart models already expose `correctionRate` and `clipboardActivityRate` from the session summary.

### Changed

- **Flux-only rates**: Manual correction rate and clipboard activity rate calculations were removed from Android and iOS SDKs. Both rates now come exclusively from Flux meta (`correction_rate`, `clipboard_activity_rate`).
- **number_of_delete**: Sent as 0 on mobile (desktop/Flux supports separate delete key; mobile only tracks backspace).
- **Example app release build**: When `key.properties` is missing, release APK now uses debug signing so `flutter build apk` produces an installable APK instead of an unsigned one.

### Technical Details

- Android and iOS FluxBridge: typing payload to Flux includes `number_of_backspace`, `number_of_delete` (0), `number_of_copy`, `number_of_paste`, `number_of_cut`. Flux meta is read for `correction_rate` and `clipboard_activity_rate` and exposed in `typing_session_summary`.
- Clipboard summary still provides raw counts (clipboard_count, copy/paste/cut counts); only the rates are computed by Flux.

## [0.0.1] - 2025-12-26

### Added

- Initial release of Synheart Behavioral SDK for Flutter
- Core SDK classes: `SynheartBehavior`, `BehaviorConfig`, `BehaviorEvent`, `BehaviorSession`, `BehaviorStats`
- Streaming API for real-time behavioral events
- Session tracking with summaries
- Manual stats polling
- Platform channel interfaces for iOS and Android
- Example Flutter app demonstrating SDK usage
- Comprehensive documentation and README

### Features

- Input interaction signals (tap, scroll, swipe gestures)
- Attention & multitasking signals (app switching, idle gaps, session stability)
- Privacy-preserving design (no text, content, or PII collected)
- Lightweight implementation (<150 KB compiled)
- Low resource usage (<2% CPU, <500 KB memory)
- Optional notification and call tracking (requires permissions)

### Platform Support

- iOS 12.0+
- Android API 21+ (Android 5.0+)
- Flutter 3.10.0+

## [0.1.0] - 2025-12-29

### Added

- Motion state inference with ML model (LAYING, MOVING, SITTING, STANDING)
- Typing session tracking and comprehensive typing metrics
- Emotion metrics integration
- Motion feature extractor for device motion signals
- Enhanced behavior session with expanded metrics
- ONNX model support for motion state prediction
- Label mapping for motion state classification

### Features

- Real-time motion state prediction using on-device ML inference
- Typing activity ratio, cadence, and burstiness metrics
- Deep focus block detection
- Enhanced behavioral metrics (focus hint, distraction score)
- Improved session summaries with motion state information

## [0.1.1] - 2025-12-30

### Changed

- Removed documentation file from repository

## [0.1.2] - 2025-12-31

### Fixed

- Fixed null casting error in Android build.gradle.kts by making signing config conditional
- Updated .gitignore to exclude Gradle cache files (.gradle/ directory)

### Changed

- Replaced `onnxruntime` with `flutter_onnxruntime` in `pubspec.yaml`
- Build configuration now gracefully handles missing key.properties file for debug builds

## [0.1.3] - 2026-01-08

### Added

- **On-Demand Metrics Calculation**: New `calculateMetricsForTimeRange()` method to calculate behavioral metrics for custom time ranges within a session
- Time range validation to ensure selected ranges are within session bounds
- Session data persistence improvements - data now persists until next session starts, enabling on-demand queries for ended sessions
- Motion state inference support for on-demand calculations

### Fixed

- Fixed session data being cleared too early (now cleared when new session starts instead of when session ends)

### Changed

- Enhanced session data management to support on-demand metric calculations for ended sessions
- Improved motion data handling with proper type conversions for nested maps

## [0.1.4] - 2026-01-23

### Changed

- **Flux Integration**: All behavioral and typing metric calculations now exclusively use synheart-flux (Rust library)
- Removed native Kotlin/Swift calculation implementations for behavioral metrics
- Removed redundant comparison fields (`behavioralMetricsFlux`, `typingSessionSummaryFlux`) from Dart models
- Updated data flow: All metrics now come directly from Flux, ensuring HSI compliance and cross-platform consistency
- Simplified codebase by removing ~1000+ lines of native calculation code

### Removed

- Native calculation functions: `computeBehavioralMetrics()`, `computeTypingSessionSummary()`, `computeIdleRatio()`, `computeFragmentedIdleRatio()`, `computeScrollJitterRate()`, `computeBurstiness()`, `computeDeepFocusBlocks()`, and related helper functions

### Breaking Changes

- **Flux is now required**: The SDK requires synheart-flux libraries to be present. If Flux is unavailable, session ending will fail with an error instead of falling back to native calculations
- Removed `behavioralMetricsFlux` and `typingSessionSummaryFlux` fields from `BehaviorSessionSummary` model (use `behavioralMetrics` and `typingSessionSummary` instead, which now contain Flux data)

### Technical Details

- All behavioral metrics (interaction intensity, distraction score, focus hint, deep focus blocks, etc.) are computed by Flux
- All typing session metrics (typing session count, average keystrokes, typing speed, etc.) are computed by Flux
- Performance information now only tracks Flux execution time
- Native code now only handles event collection, session management, and Flux integration
