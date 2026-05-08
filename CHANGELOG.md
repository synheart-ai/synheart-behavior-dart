# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-05-07

OSS-launch refactor pass.

### Breaking
- Removed `motion_state_inference` public export and the underlying
  `MotionFeatureExtractor` / `MotionSignalCollector` classifier path.
  Motion classification is no longer part of the public surface.
- Removed `behavior_window_aggregator`, `behavior_window_features`, and
  `behavior_feature_extractor` (already deprecated; window features
  moved out of the real-time event stream).

### Added
- `motion_sample` model export — raw accelerometer sample batching for
  callers that need to do their own classification.
- `core/logger` export — pluggable logging shared with the rest of the
  Synheart SDK family.
- `app_switch` event type and improved gesture/touch handling on both
  platforms.

### Changed
- Renamed Android package `com.synheart` → `ai.synheart` to match the
  org-wide naming convention.
- Cleaned internal-only language and stale runtime references from
  source comments and README.

## [0.2.1] - 2026-05-06

Initial open-source release of the Synheart Behavior SDK for Flutter.

The SDK collects privacy-preserving behavioral signals (taps, scrolls,
swipes, app switches, idle gaps, typing session counts) on iOS and
Android. No text, content, or PII is captured. Behavioral and typing
metrics are computed locally by the native iOS / Android implementations
and surfaced through `BehaviorSessionSummary` (`behavioralMetrics`,
`typingSessionSummary`).

### Public surface
- `SynheartBehavior`, `BehaviorConfig`, `BehaviorEvent`,
  `BehaviorSession`, `BehaviorSessionSummary`, `BehavioralMetrics`,
  `TypingSessionSummary`, `BehaviorStats`.
- Streaming API for real-time behavioral events; session-tracking API
  with summaries; manual stats polling.
- On-demand metrics for ended sessions:
  `calculateMetricsForTimeRange()`.

### Platform support
- iOS 12.0+
- Android API 21+ (Android 5.0+)
- Flutter 3.10.0+

[Unreleased]: https://github.com/synheart-ai/synheart-behavior-flutter/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/synheart-ai/synheart-behavior-flutter/releases/tag/v0.3.0
[0.2.1]: https://github.com/synheart-ai/synheart-behavior-flutter/releases/tag/v0.2.1
