import 'dart:async';
import 'package:flutter/services.dart';
import 'models/behavior_config.dart';
import 'models/behavior_event.dart';
import 'models/behavior_session.dart'
    show BehaviorSession, BehaviorSessionSummary;
import 'models/behavior_stats.dart';

/// Main entry point for the Synheart Behavioral SDK.
///
/// This SDK collects digital behavioral signals from smartphones without
/// collecting any text, content, or PII - only timing-based signals.
class SynheartBehavior {
  static const MethodChannel _channel = MethodChannel('ai.synheart.behavior');

  final BehaviorConfig _config;
  final StreamController<BehaviorEvent> _eventController =
      StreamController<BehaviorEvent>.broadcast();
  final Map<String, BehaviorSession> _activeSessions = {};

  bool _initialized = false;
  String? _currentSessionId;

  SynheartBehavior._(this._config);

  /// Initialize the Synheart Behavioral SDK with the given configuration.
  ///
  /// This method must be called before using any other SDK methods.
  /// It sets up the native platform channels and starts collecting behavioral signals.
  static Future<SynheartBehavior> initialize({
    BehaviorConfig? config,
  }) async {
    final behavior = SynheartBehavior._(config ?? const BehaviorConfig());

    try {
      // Set up event stream listener
      _channel.setMethodCallHandler(behavior._handleMethodCall);

      // Initialize native SDK
      await _channel.invokeMethod('initialize', config?.toJson() ?? {});

      behavior._initialized = true;
      return behavior;
    } catch (e) {
      throw Exception('Failed to initialize Synheart Behavioral SDK: $e');
    }
  }

  /// Stream of behavioral events emitted by the SDK.
  ///
  /// Subscribe to this stream to receive real-time behavioral signals.
  Stream<BehaviorEvent> get onEvent => _eventController.stream;

  /// Handle method calls from the native platform.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onEvent':
        final eventData = call.arguments as Map<dynamic, dynamic>;
        final event = BehaviorEvent.fromJson(
          Map<String, dynamic>.from(eventData),
        );
        _eventController.add(event);
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} is not implemented',
        );
    }
  }

  /// Start a new behavioral tracking session.
  ///
  /// Returns a [BehaviorSession] object that can be used to end the session
  /// and retrieve a summary.
  Future<BehaviorSession> startSession({String? sessionId}) async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    final sessionIdToUse = sessionId ??
        '${_config.sessionIdPrefix ?? 'SESS'}-${DateTime.now().millisecondsSinceEpoch}';

    try {
      await _channel
          .invokeMethod('startSession', {'sessionId': sessionIdToUse});
      _currentSessionId = sessionIdToUse;

      final session = BehaviorSession(
        sessionId: sessionIdToUse,
        startTimestamp: DateTime.now().millisecondsSinceEpoch,
        endCallback: _endSession,
      );

      _activeSessions[sessionIdToUse] = session;
      return session;
    } catch (e) {
      throw Exception('Failed to start session: $e');
    }
  }

  /// End a session by its ID and return summary.
  Future<BehaviorSessionSummary> _endSession(String sessionId) async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      final result = await _channel.invokeMethod('endSession', {
        'sessionId': sessionId,
      });

      final session = _activeSessions[sessionId];
      if (session == null) {
        throw Exception('Session not found: $sessionId');
      }

      final summary = BehaviorSessionSummary.fromJson(
        Map<String, dynamic>.from(result as Map),
      );

      _activeSessions.remove(sessionId);
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
      }

      return summary;
    } catch (e) {
      throw Exception('Failed to end session: $e');
    }
  }

  /// Get current rolling statistics snapshot.
  ///
  /// Returns a [BehaviorStats] object containing current behavioral metrics.
  Future<BehaviorStats> getCurrentStats() async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      final result = await _channel.invokeMethod('getCurrentStats');
      return BehaviorStats.fromJson(
        Map<String, dynamic>.from(result as Map),
      );
    } catch (e) {
      throw Exception('Failed to get current stats: $e');
    }
  }

  /// Enable or disable specific signal collection at runtime.
  ///
  /// Useful for dynamically adjusting what signals are collected based on
  /// user preferences or app state.
  Future<void> updateConfig(BehaviorConfig config) async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      await _channel.invokeMethod('updateConfig', config.toJson());
    } catch (e) {
      throw Exception('Failed to update config: $e');
    }
  }

  /// Dispose of the SDK instance and clean up resources.
  ///
  /// Call this when you're done using the SDK to free up resources.
  Future<void> dispose() async {
    if (!_initialized) return;

    try {
      // End all active sessions
      final sessions = List<BehaviorSession>.from(_activeSessions.values);
      for (final session in sessions) {
        try {
          await session.end();
        } catch (_) {
          // Ignore errors when disposing
        }
      }
      _activeSessions.clear();

      // Stop native SDK
      await _channel.invokeMethod('dispose');

      // Close event stream
      await _eventController.close();

      _initialized = false;
    } catch (e) {
      throw Exception('Failed to dispose SDK: $e');
    }
  }

  /// Check if the SDK is currently initialized.
  bool get isInitialized => _initialized;

  /// Get the current active session ID, if any.
  String? get currentSessionId => _currentSessionId;
}
