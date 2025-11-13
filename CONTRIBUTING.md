# Contributing to Synheart Behavioral SDK

Thank you for your interest in contributing to the Synheart Behavioral SDK!

## Development Setup

1. Clone the repository:
```bash
git clone https://github.com/synheart-ai/synheart-behavior-flutter.git
cd synheart-behavior-flutter
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the example app:
```bash
cd example
flutter run
```

## Code Style

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide
- Run `flutter analyze` before committing
- Ensure all tests pass

## Testing

- Write unit tests for new features
- Test on both iOS and Android platforms
- Ensure privacy requirements are met (no PII collection)

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Add tests if applicable
4. Update documentation
5. Submit a pull request with a clear description

## Privacy Requirements

**Critical**: This SDK must never collect:
- Text content
- Keystroke content
- Screen content
- PII (Personally Identifiable Information)
- App content

Only timing-based signals are allowed.

## Questions?

Feel free to open an issue or contact the maintainers.

