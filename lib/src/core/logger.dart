import 'package:flutter/foundation.dart';

/// Log levels for the behavior SDK.
enum BehaviorLogLevel { debug, info, warning, error }

/// Logger interface the behavior SDK calls internally. Consumers inject a
/// concrete implementation via [setBehaviorLogger] so logs flow into the
/// host app's logging pipeline (Crashlytics, structured channels, etc.)
/// instead of being dumped to stdout via `print()`.
///
/// Mirrors the pattern used by `synheart_wear`'s `SynheartLogger` so
/// integrators can wire both SDKs to the same backend.
abstract class SynheartBehaviorLogger {
  void log(
    BehaviorLogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]);

  void debug(String message) => log(BehaviorLogLevel.debug, message);
  void info(String message) => log(BehaviorLogLevel.info, message);
  void warning(String message, [Object? error]) =>
      log(BehaviorLogLevel.warning, message, error);
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      log(BehaviorLogLevel.error, message, error, stackTrace);
}

/// Default logger — stays silent for debug/info unless [kDebugMode] is on.
/// Errors are always surfaced since swallowing them silently hides real
/// problems (e.g. model-load failures). Apps that want verbose traces in
/// release should install a custom logger via [setBehaviorLogger].
class DefaultBehaviorLogger implements SynheartBehaviorLogger {
  const DefaultBehaviorLogger();

  @override
  void log(
    BehaviorLogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!kDebugMode && level != BehaviorLogLevel.error) return;
    final prefix = switch (level) {
      BehaviorLogLevel.debug => '🔍 [Behavior DEBUG]',
      BehaviorLogLevel.info => 'ℹ️ [Behavior]',
      BehaviorLogLevel.warning => '⚠️ [Behavior]',
      BehaviorLogLevel.error => '❌ [Behavior]',
    };
    final line = error != null
        ? '$prefix $message\n  error: $error'
            '${stackTrace != null ? "\n$stackTrace" : ""}'
        : '$prefix $message';
    debugPrint(line);
  }

  @override
  void debug(String message) => log(BehaviorLogLevel.debug, message);
  @override
  void info(String message) => log(BehaviorLogLevel.info, message);
  @override
  void warning(String message, [Object? error]) =>
      log(BehaviorLogLevel.warning, message, error);
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      log(BehaviorLogLevel.error, message, error, stackTrace);
}

SynheartBehaviorLogger _logger = const DefaultBehaviorLogger();

/// Install a custom logger. The forwarder the host app installs here is
/// the integration seam between this SDK's internal events and whatever
/// channel the app routes them to (e.g. `SynheartLogger.stream` in apps
/// that use `synheart_core`).
void setBehaviorLogger(SynheartBehaviorLogger logger) {
  _logger = logger;
}

/// Get the currently-installed logger (internal SDK use).
SynheartBehaviorLogger get behaviorLogger => _logger;

// Convenience top-level functions — mirror synheart_wear so the migration
// from `print(...)` is a mechanical substitution.
void logDebug(String message) => _logger.debug(message);
void logInfo(String message) => _logger.info(message);
void logWarning(String message, [Object? error]) =>
    _logger.warning(message, error);
void logError(String message, [Object? error, StackTrace? stackTrace]) =>
    _logger.error(message, error, stackTrace);
