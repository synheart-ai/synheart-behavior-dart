# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
