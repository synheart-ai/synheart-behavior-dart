import 'dart:async';
// dart:io was only used for Platform in _generateDeviceId (commented out)
// import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'models/behavior_config.dart';
import 'models/behavior_event.dart';
import 'models/behavior_session.dart'
    show BehaviorSession, BehaviorSessionSummary;
import 'models/behavior_stats.dart';
import 'models/motion_sample.dart';
// Window features - commented out (not needed for real-time event tracking)
// import 'models/behavior_window_features.dart';
// import 'behavior_window_aggregator.dart';
// import 'behavior_feature_extractor.dart';
import 'behavior_gesture_detector.dart'
    show BehaviorGestureDetector, BehaviorTextField;

/// Main entry point for the Synheart Behavioral SDK.
///
/// This SDK collects digital behavioral signals from smartphones without
/// collecting any text, content, or PII - only timing-based signals.
class SynheartBehavior {
  static const MethodChannel _channel = MethodChannel('ai.synheart.behavior');

  final BehaviorConfig _config;
  final StreamController<BehaviorEvent> _eventController =
      StreamController<BehaviorEvent>.broadcast();
  final StreamController<List<MotionSample>> _motionSampleController =
      StreamController<List<MotionSample>>.broadcast();
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

  // User/device IDs - commented out (not currently used)
  // String? _userId;
  // String? _deviceId;

  /// Internal method to handle events from Flutter gesture detector.
  ///
  /// Silently drops events after `dispose()` has closed the controller.
  /// The gesture detector widget may still be mounted and firing taps/
  /// scrolls after the SDK has been shut down (session stop + dispose
  /// race); adding to a closed controller would throw
  /// "Bad state: Cannot add new events after calling close".
  void _handleFlutterEvent(BehaviorEvent event) {
    if (_eventController.isClosed) return;

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

  /// Optional callback invoked immediately when an event is received from native,
  /// before adding to the stream. Use this to avoid missing events that arrive
  /// before stream listeners are attached.
  void Function(BehaviorEvent)? _immediateEventCallback;

  SynheartBehavior._(this._config);

  /// Initialize the Synheart Behavioral SDK with the given configuration.
  ///
  /// This method must be called before using any other SDK methods.
  /// It sets up the native platform channels and starts collecting behavioral signals.
  /// [onEventCallback] if set is called synchronously for each event from native
  /// (before the event is added to [onEvent]), so the host never misses events.
  static Future<SynheartBehavior> initialize({
    BehaviorConfig? config,
    void Function(BehaviorEvent)? onEventCallback,
  }) async {
    final effectiveConfig = config ?? const BehaviorConfig();
    final behavior = SynheartBehavior._(effectiveConfig);
    behavior._immediateEventCallback = onEventCallback;

    try {
      // Set up event stream listener
      _channel.setMethodCallHandler(behavior._handleMethodCall);

      // Initialize native SDK
      await _channel.invokeMethod('initialize', effectiveConfig.toJson());

      // Motion-state classification was previously inferred locally via an
      // ONNX SVC. As of RFC-MOTION-STATE-0001, that path is removed — raw
      // accel samples are forwarded to the engine runtime via
      // `BehaviorConfig.emitRawMotionSamples`, and `MotionStateHead` in
      // `synheart-state-runtime` does the classification.

      // Window features - commented out (not needed for real-time event tracking)
      // behavior._startWindowUpdates();

      // User/device IDs - commented out (not currently used)
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

  /// Stream of raw accelerometer sample batches.
  ///
  /// Each event is a list of ~50 samples representing a 1-second window at
  /// 50 Hz (batched on the native side to keep MethodChannel overhead low).
  /// Consumers — typically `synheart-core-flutter`'s `BehaviorModule` —
  /// forward these via the runtime's `push_accel` FFI so the engine's
  /// `session-runtime` can derive features and `MotionStateHead` (per
  /// RFC-MOTION-STATE-0001) can classify posture/motion.
  ///
  /// Phase 3 wiring: the behavior SDK is the *collector*, not the inferrer.
  /// Native emission is implemented behind the
  /// `BehaviorConfig.emitRawMotionSamples` flag once the platform side
  /// (Swift `MotionSignalCollector`, Kotlin equivalent) lands.
  Stream<List<MotionSample>> get onMotionSample =>
      _motionSampleController.stream;

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
        // Native sends nested map: {"event": {"event_type": "...", "metrics": {...}}}
        final inner = eventData['event'] ?? eventData;
        final innerMap = inner is Map<dynamic, dynamic> ? inner : null;
        final eventTypeStr = innerMap?['event_type'];
        final metricsVal = innerMap?['metrics'];
        if (eventTypeStr != null) {
          debugPrint(
              'BEHAVIOR_PIPELINE: [BehaviorSDK] onEvent from native: event_type=$eventTypeStr metrics=$metricsVal');
        } else {
          final topKeys = eventData.keys.map((k) => k.toString()).toList();
          debugPrint(
              'BEHAVIOR_PIPELINE: [BehaviorSDK] onEvent from native: (nested keys missing) topLevelKeys=$topKeys');
        }

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

          // Notify immediate callback first so core never misses an event
          _immediateEventCallback?.call(event);
          if (_eventController.isClosed) {
            // Dispose raced ahead of a native event. Native side will stop
            // emitting once `dispose()` completes; drop the straggler.
            debugPrint(
                'BEHAVIOR_PIPELINE: [BehaviorSDK] onEvent dropped — controller closed');
            return;
          }
          _eventController.add(event);
          debugPrint(
              'BEHAVIOR_PIPELINE: [BehaviorSDK] onEvent parsed and added: ${event.eventType}');
          // Window features - commented out (not needed for real-time event tracking)
          // Always add to window aggregator (events are time-based, not session-based)
          // _windowAggregator.addEvent(event);
        } catch (e, st) {
          debugPrint(
              'BEHAVIOR_PIPELINE: [BehaviorSDK] onEvent parse error: $e');
          debugPrint('[BehaviorSDK] onEvent parse error: $e');
          debugPrint('[BehaviorSDK] stack: $st');
        }
        break;
      case 'onMotionSampleBatch':
        // Native side emits a periodic batch of raw 50 Hz accel samples for
        // the runtime to consume via push_accel. See [onMotionSample] for the
        // contract. Payload shape:
        //   { "samples": [ {ts_ms, ax, ay, az}, ... ] }
        try {
          final args = call.arguments as Map<dynamic, dynamic>;
          final rawList = args['samples'];
          if (rawList is! List) break;
          final samples = <MotionSample>[];
          for (final item in rawList) {
            if (item is Map) {
              samples.add(MotionSample.fromMap(item));
            }
          }
          if (samples.isEmpty || _motionSampleController.isClosed) break;
          _motionSampleController.add(samples);
        } catch (e) {
          debugPrint('[BehaviorSDK] onMotionSampleBatch parse error: $e');
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
      final summary = BehaviorSessionSummary.fromJson(resultMap);
      // print('Summary parsed successfully. Session ID: ${summary.sessionId}');

      // Motion-state classification moved to the engine runtime per
      // RFC-MOTION-STATE-0001. The session summary no longer carries
      // `motion_state` / `motion_data`; consumers read motion state from
      // the runtime's HSI snapshot via `synheart-core-flutter`'s
      // `BehaviorModule.motionStateUpdates`.

      _activeSessions.remove(sessionId);
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
      }

      return summary;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('SynheartBehavior: endSession failed: $e');
        debugPrint('$stackTrace');
      }
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
      await _motionSampleController.close();
      // Window features - commented out (not needed for real-time event tracking)
      // await _shortWindowController.close();
      // await _longWindowController.close();

      // Window features - commented out (not needed for real-time event tracking)
      // Clear window aggregator
      // _windowAggregator.clear();

      _initialized = false;
    } catch (e) {
      throw Exception('Failed to dispose SDK: $e');
    }
  }

  /// Send an event from Dart to the native SDK.
  /// This is used by BehaviorGestureDetector to send Flutter gesture events
  /// to the native SDK for storage in session data.
  ///
  /// Silently no-ops when the SDK is not initialized. The gesture detector
  /// fires-and-forgets this call, so an exception after dispose would
  /// escape as an unhandled async error; returning quietly is the safe
  /// behavior for the "stragglers arriving after stop" case.
  Future<void> sendEvent(BehaviorEvent event) async {
    if (!_initialized) return;

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

  /// Calculate metrics for a specific time range within a session.
  ///
  /// This method retrieves events and motion data for the specified time range
  /// and calculates behavioral metrics dynamically using lambda/mu parameters.
  ///
  /// [startTimestampSeconds] - Start timestamp in seconds (Unix epoch)
  /// [endTimestampSeconds] - End timestamp in seconds (Unix epoch)
  /// [sessionId] - Optional session ID. If not provided, uses the current active session.
  ///
  /// Returns a map containing calculated metrics including:
  /// - behavioral_metrics: Interaction intensity, task switch rate, etc.
  /// - device_context: Screen brightness, orientation changes
  /// - system_state: Internet, DND, charging status
  /// - activity_summary: Event counts and app switches
  /// - notification_summary: Notification metrics
  /// - typing_session_summary: Typing metrics (if available)
  Future<Map<String, dynamic>> calculateMetricsForTimeRange({
    required int startTimestampSeconds,
    required int endTimestampSeconds,
    String? sessionId,
  }) async {
    if (!_initialized) {
      throw Exception(
        'SDK not initialized. Call SynheartBehavior.initialize() first.',
      );
    }

    try {
      final result = await _channel.invokeMethod(
        'calculateMetricsForTimeRange',
        {
          'startTimestampMs': startTimestampSeconds * 1000,
          'endTimestampMs': endTimestampSeconds * 1000,
          'sessionId': sessionId ?? _currentSessionId,
        },
      );
      final metrics = Map<String, dynamic>.from(result as Map);

      // Motion-state classification moved to the engine runtime per
      // RFC-MOTION-STATE-0001. The behavior SDK no longer surfaces
      // `motion_state` / `motion_data` on this map; consumers read motion
      // state from the runtime's HSI snapshot.

      return metrics;
    } catch (e) {
      throw Exception('Failed to calculate metrics for time range: $e');
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
      behavior: this,
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
  // User/device ID generation - commented out (not currently used)
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
