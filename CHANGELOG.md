# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-13

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
- Input interaction signals (keystroke timing, scroll dynamics, gesture activity)
- Attention & multitasking signals (app switching, idle gaps, session stability)
- Privacy-preserving design (no text, content, or PII collected)
- Lightweight implementation (<150 KB compiled)
- Low resource usage (<2% CPU, <500 KB memory)

## [Unreleased]

### Planned
- Motion-lite signals (device orientation, shake patterns)
- Cognitive fragmentation index
- Per-app behavior profiles
- Fatigue markers
- On-device personalization (behavior embeddings)

