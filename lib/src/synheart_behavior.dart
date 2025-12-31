import 'dart:async';
// dart:io was only used for Platform in _generateDeviceId (commented out)
// import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'models/behavior_config.dart';
import 'models/behavior_event.dart';
import 'models/behavior_session.dart'
    show BehaviorSession, BehaviorSessionSummary;
import 'models/behavior_stats.dart';
// Window features - commented out (not needed for real-time event tracking)
// import 'models/behavior_window_features.dart';
// import 'behavior_window_aggregator.dart';
// import 'behavior_feature_extractor.dart';
import 'behavior_gesture_detector.dart'
    show BehaviorGestureDetector, BehaviorTextField;
import 'motion_state_inference.dart';

/// Main entry point for the Synheart Behavioral SDK.
///
/// This SDK collects digital behavioral signals from smartphones without
/// collecting any text, content, or PII - only timing-based signals.
class SynheartBehavior {
  static const MethodChannel _channel = MethodChannel('ai.synheart.behavior');

  final BehaviorConfig _config;
  final StreamController<BehaviorEvent> _eventController =
      StreamController<BehaviorEvent>.broadcast();
  // Window features - commented out (not needed for real-time event tracking)
  // final StreamController<BehaviorWindowFeatures> _shortWindowController =
  //     StreamController<BehaviorWindowFeatures>.broadcast();
  // final StreamController<BehaviorWindowFeatures> _longWindowController =
  //     StreamController<BehaviorWindowFeatures>.broadcast();
  final Map<String, BehaviorSession> _activeSessions = {};

  // Window features - commented out (not needed for real-time event tracking)
  // final WindowAggregator _windowAggregator = WindowAggregator();
  // final BehaviorFeatureExtractor _featureExtractor = BehaviorFeatureExtractor();
  // Timer? _windowUpdateTimer;

  // User/device IDs - only used for HSI payloads (window features)
  // String? _userId;
  // String? _deviceId;

  /// Internal method to handle events from Flutter gesture detector
  void _handleFlutterEvent(BehaviorEvent event) {
    // Replace "current" session ID if needed
    var eventWithSessionId = event;
    if (event.sessionId == "current" && _currentSessionId != null) {
      // Create new event with correct session ID
      eventWithSessionId = BehaviorEvent(
        eventId: event.eventId,
        sessionId: _currentSessionId!,
        timestamp: DateTime.parse(event.timestamp),
        eventType: event.eventType,
        metrics: event.metrics,
      );
    }

    _eventController.add(eventWithSessionId);
    // Window features - commented out (not needed for real-time event tracking)
    // _windowAggregator.addEvent(eventWithSessionId);
  }

  bool _initialized = false;
  String? _currentSessionId;
  final MotionStateInference _motionStateInference = MotionStateInference();

  SynheartBehavior._(this._config);

  /// Initialize the Synheart Behavioral SDK with the given configuration.
  ///
  /// This method must be called before using any other SDK methods.
  /// It sets up the native platform channels and starts collecting behavioral signals.
  static Future<SynheartBehavior> initialize({BehaviorConfig? config}) async {
    final behavior = SynheartBehavior._(config ?? const BehaviorConfig());

    try {
      // Set up event stream listener
      _channel.setMethodCallHandler(behavior._handleMethodCall);

      // Initialize native SDK
      await _channel.invokeMethod('initialize', config?.toJson() ?? {});

      // Load motion state inference model
      try {
        await behavior._motionStateInference.loadModel();
      } catch (e) {
        print('Warning: Failed to load motion state inference model: $e');
        // Continue initialization even if model loading fails
      }

      // Window features - commented out (not needed for real-time event tracking)
      // behavior._startWindowUpdates();

      // User/device IDs - only used for HSI payloads (window features)
      // behavior._userId = config?.userId ?? SynheartBehavior._generateUserId();
      // behavior._deviceId =
      //     config?.deviceId ?? SynheartBehavior._generateDeviceId();

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

  // Window features - commented out (not needed for real-time event tracking)
  // /// Stream of 30-second window features.
  // ///
  // /// Emits updated features every 5 seconds for the rolling 30-second window.
  // Stream<BehaviorWindowFeatures> get onShortWindowFeatures =>
  //     _shortWindowController.stream;
  //
  // /// Stream of 5-minute window features.
  // ///
  // /// Emits updated features every 30 seconds for the rolling 5-minute window.
  // Stream<BehaviorWindowFeatures> get onLongWindowFeatures =>
  //     _longWindowController.stream;

  /// Convert nested Map<dynamic, dynamic> to Map<String, dynamic> recursively
  Map<String, dynamic> _convertMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) {
      if (value is Map) {
        return MapEntry(
          key.toString(),
          _convertMap(value),
        );
      } else if (value is List) {
        return MapEntry(
          key.toString(),
          value.map((item) {
            if (item is Map) {
              return _convertMap(item);
            }
            return item;
          }).toList(),
        );
      }
      return MapEntry(key.toString(), value);
    });
  }

  /// Handle method calls from the native platform.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onEvent':
        final eventData = call.arguments as Map<dynamic, dynamic>;

        try {
          // Convert the entire map structure properly, handling nested maps
          final convertedData = _convertMap(eventData);
          var event = BehaviorEvent.fromJson(convertedData);

          // Replace "current" session ID with actual session ID if available
          // If no session is active, still add events (they'll be associated when session starts)
          if (event.sessionId == "current") {
            if (_currentSessionId != null) {
              event = BehaviorEvent(
                eventId: event.eventId,
                sessionId: _currentSessionId!,
                timestamp: DateTime.parse(event.timestamp),
                eventType: event.eventType,
                metrics: event.metrics,
              );
            }
            // Even if no session, add events to window (they'll be used when session starts)
          }

          _eventController.add(event);
          // Window features - commented out (not needed for real-time event tracking)
          // Always add to window aggregator (events are time-based, not session-based)
          // _windowAggregator.addEvent(event);
        } catch (e) {
          // Silently handle parsing errors to avoid console spam
        }
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
      await _channel.invokeMethod('startSession', {
        'sessionId': sessionIdToUse,
      });
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
    // print('SDK _endSession called with sessionId: $sessionId');
    // print('_initialized: $_initialized');
    // print('_activeSessions keys: ${_activeSessions.keys.toList()}');

    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      // print('Calling native endSession with sessionId: $sessionId');
      final result = await _channel
          .invokeMethod('endSession', {'sessionId': sessionId}).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('endSession timed out after 10 seconds');
        },
      );
      // print('Native endSession returned: ${result.runtimeType}');
      if (result == null) {
        throw Exception('Native endSession returned null');
      }

      final session = _activeSessions[sessionId];
      if (session == null) {
        // print('ERROR: Session not found in _activeSessions: $sessionId');
        throw Exception('Session not found: $sessionId');
      }

      // Ensure result is properly converted to Map<String, dynamic>
      final resultMap = result is Map
          ? Map<String, dynamic>.from(result)
          : throw Exception('Invalid result type: ${result.runtimeType}');

      // print('Parsing summary from resultMap...');
      var summary = BehaviorSessionSummary.fromJson(resultMap);
      // print('Summary parsed successfully. Session ID: ${summary.sessionId}');

      // Run motion state inference if motion data is available
      if (summary.motionData != null && summary.motionData!.isNotEmpty) {
        if (!_motionStateInference.isLoaded) {
          try {
            await _motionStateInference.loadModel();
          } catch (e) {
            print('ERROR: Failed to load model: $e');
          }
        }

        if (_motionStateInference.isLoaded) {
          try {
            final motionState = await _motionStateInference.inferMotionState(
              summary.motionData!,
            );

            // Create updated summary with motion state
            summary = BehaviorSessionSummary(
              sessionId: summary.sessionId,
              startAt: summary.startAt,
              endAt: summary.endAt,
              microSession: summary.microSession,
              os: summary.os,
              appId: summary.appId,
              appName: summary.appName,
              sessionSpacing: summary.sessionSpacing,
              motionState: motionState,
              deviceContext: summary.deviceContext,
              activitySummary: summary.activitySummary,
              behavioralMetrics: summary.behavioralMetrics,
              notificationSummary: summary.notificationSummary,
              systemState: summary.systemState,
              typingSessionSummary: summary.typingSessionSummary,
              motionData: summary.motionData,
            );
          } catch (e) {
            print('ERROR: Failed to run motion state inference: $e');
            // Continue without motion state if inference fails
          }
        }
      }

      _activeSessions.remove(sessionId);
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
      }

      return summary;
    } catch (e, stackTrace) {
      // print('Error ending session: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to end session: $e ');
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
      return BehaviorStats.fromJson(Map<String, dynamic>.from(result as Map));
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

  /// Check if notification permission is granted.
  ///
  /// Returns `true` if notification access is enabled, `false` otherwise.
  /// On Android, this checks if the NotificationListenerService is enabled.
  /// On iOS, this checks if notification authorization is granted.
  Future<bool> checkNotificationPermission() async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      final result = await _channel.invokeMethod('checkNotificationPermission');
      return result as bool? ?? false;
    } catch (e) {
      throw Exception('Failed to check notification permission: $e');
    }
  }

  /// Request notification permission.
  ///
  /// On Android, this opens the system settings where the user can enable
  /// notification access for the app.
  /// On iOS, this requests notification authorization directly.
  Future<bool> requestNotificationPermission() async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      final result = await _channel.invokeMethod(
        'requestNotificationPermission',
      );
      return result as bool? ?? false;
    } catch (e) {
      throw Exception('Failed to request notification permission: $e');
    }
  }

  /// Check if call permission is granted.
  ///
  /// Returns `true` if phone state permission is granted, `false` otherwise.
  /// On Android, this checks if READ_PHONE_STATE permission is granted.
  /// On iOS, call monitoring doesn't require explicit permission.
  Future<bool> checkCallPermission() async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      final result = await _channel.invokeMethod('checkCallPermission');
      return result as bool? ?? false;
    } catch (e) {
      throw Exception('Failed to check call permission: $e');
    }
  }

  /// Request call permission.
  ///
  /// On Android, this requests READ_PHONE_STATE permission at runtime.
  /// On iOS, call monitoring doesn't require explicit permission.
  Future<void> requestCallPermission() async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      await _channel.invokeMethod('requestCallPermission');
    } catch (e) {
      throw Exception('Failed to request call permission: $e');
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

      // Window features - commented out (not needed for real-time event tracking)
      // Stop window updates
      // _windowUpdateTimer?.cancel();
      // _windowUpdateTimer = null;

      // Close event streams
      await _eventController.close();
      // Window features - commented out (not needed for real-time event tracking)
      // await _shortWindowController.close();
      // await _longWindowController.close();

      // Window features - commented out (not needed for real-time event tracking)
      // Clear window aggregator
      // _windowAggregator.clear();

      // Dispose motion state inference
      await _motionStateInference.dispose();

      _initialized = false;
    } catch (e) {
      throw Exception('Failed to dispose SDK: $e');
    }
  }

  /// Send an event from Dart to the native SDK.
  /// This is used by BehaviorGestureDetector to send Flutter gesture events
  /// to the native SDK for storage in session data.
  Future<void> sendEvent(BehaviorEvent event) async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      // Replace "current" session ID with actual session ID if available
      final eventToSend =
          event.sessionId == "current" && _currentSessionId != null
              ? BehaviorEvent(
                  eventId: event.eventId,
                  sessionId: _currentSessionId!,
                  timestamp: DateTime.parse(event.timestamp),
                  eventType: event.eventType,
                  metrics: event.metrics,
                )
              : event;

      await _channel.invokeMethod('sendEvent', eventToSend.toJson());
    } catch (e) {
      throw Exception('Failed to send event to native SDK: $e');
    }
  }

  /// Check if the SDK is currently initialized.
  bool get isInitialized => _initialized;

  /// Get the current active session ID, if any.
  String? get currentSessionId => _currentSessionId;

  /// Get a widget that wraps your app to detect Flutter gestures.
  ///
  /// This is needed because Flutter widgets are not native views,
  /// so native touch listeners won't capture Flutter interactions.
  Widget wrapWithGestureDetector(Widget child) {
    return BehaviorGestureDetector(
      sessionId: _currentSessionId ?? "current",
      onEvent: _handleFlutterEvent,
      child: child,
    );
  }

  /// Get a TextField for behavior tracking.
  ///
  /// Text input interactions are captured as tap events.
  Widget createBehaviorTextField({
    TextEditingController? controller,
    InputDecoration? decoration,
    int? maxLines,
  }) {
    return BehaviorTextField(
      controller: controller,
      decoration: decoration,
      maxLines: maxLines,
    );
  }

  // Window features - commented out (not needed for real-time event tracking)
  // /// Get features for a specific window type.
  // BehaviorWindowFeatures? getWindowFeatures(WindowType windowType) {
  //   if (!_initialized) return null;
  //
  //   final events = _windowAggregator.getWindowEvents(windowType);
  //   final windowDurationMs = _windowAggregator.getWindowDurationMs(windowType);
  //
  //   return _featureExtractor.extractFeatures(
  //     events,
  //     windowType,
  //     windowDurationMs,
  //   );
  // }
  //
  // /// Convert window features to HSI (Human State Inference) payload format.
  // ///
  // /// Returns a JSON-compatible map matching the Behavior → HSI Fusion Table specification.
  // ///
  // /// Example:
  // /// ```dart
  // /// final features = behavior.getWindowFeatures(WindowType.short);
  // /// if (features != null) {
  // ///   final payload = behavior.toHSIPayload(features);
  // ///   // Send payload to HSI service
  // /// }
  // /// ```
  // Map<String, dynamic>? toHSIPayload(BehaviorWindowFeatures? features) {
  //   if (features == null || !_initialized) return null;
  //
  //   return features.toHSIPayload(
  //     userId: _userId ?? SynheartBehavior._generateUserId(),
  //     deviceId: _deviceId ?? SynheartBehavior._generateDeviceId(),
  //     behaviorVersion: _config.behaviorVersion,
  //     consentBehavior: _config.consentBehavior,
  //   );
  // }

  // User/device ID generation - only used for HSI payloads (window features)
  // /// Generate an anonymous user ID.
  // static String _generateUserId() {
  //   // Generate a simple anonymous ID (in production, use proper anonymization)
  //   final timestamp = DateTime.now().millisecondsSinceEpoch;
  //   final random = (timestamp % 1000000).toRadixString(16);
  //   return 'anon_$random';
  // }
  //
  // /// Generate a device ID based on platform.
  // static String _generateDeviceId() {
  //   final platform = Platform.isAndroid
  //       ? 'android'
  //       : (Platform.isIOS ? 'ios' : 'unknown');
  //   // In production, you might want to use device_info_plus package for more details
  //   return 'synheart_${platform}_${Platform.operatingSystemVersion.split(' ').first}';
  // }

  // Window features - commented out (not needed for real-time event tracking)
  // int _longWindowUpdateCounter = 0;
  //
  // /// Start periodic window feature updates.
  // void _startWindowUpdates() {
  //   // Update short window every 5 seconds, long window every 30 seconds
  //   _windowUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
  //     if (!_initialized) return;
  //
  //     // Always update short window
  //     final shortFeatures = getWindowFeatures(WindowType.short);
  //     if (shortFeatures != null) {
  //       _shortWindowController.add(shortFeatures);
  //     }
  //
  //     // Update long window every 30 seconds (every 6th update)
  //     _longWindowUpdateCounter++;
  //     if (_longWindowUpdateCounter >= 6) {
  //       _longWindowUpdateCounter = 0;
  //       final longFeatures = getWindowFeatures(WindowType.long);
  //       if (longFeatures != null) {
  //         _longWindowController.add(longFeatures);
  //       }
  //     }
  //   });
  // }
}
