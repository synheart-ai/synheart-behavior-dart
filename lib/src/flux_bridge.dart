import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI bindings to synheart-flux Rust library for behavioral metrics computation.
///
/// This bridge allows calling the Rust implementation of behavioral metrics
/// (distraction score, focus hint, burstiness, etc.) directly from Dart,
/// ensuring consistent HSI-compliant output across all platforms.

// FFI function signatures
typedef FluxBehaviorToHsiC = Pointer<Utf8> Function(Pointer<Utf8> json);
typedef FluxBehaviorToHsiDart = Pointer<Utf8> Function(Pointer<Utf8> json);

typedef FluxBehaviorProcessorNewC = Pointer<Void> Function(
    Int32 baselineWindow);
typedef FluxBehaviorProcessorNewDart = Pointer<Void> Function(
    int baselineWindow);

typedef FluxBehaviorProcessorFreeC = Void Function(Pointer<Void> processor);
typedef FluxBehaviorProcessorFreeDart = void Function(Pointer<Void> processor);

typedef FluxBehaviorProcessorProcessC = Pointer<Utf8> Function(
    Pointer<Void> processor, Pointer<Utf8> json);
typedef FluxBehaviorProcessorProcessDart = Pointer<Utf8> Function(
    Pointer<Void> processor, Pointer<Utf8> json);

typedef FluxBehaviorProcessorSaveBaselinesC = Pointer<Utf8> Function(
    Pointer<Void> processor);
typedef FluxBehaviorProcessorSaveBaselinesDart = Pointer<Utf8> Function(
    Pointer<Void> processor);

typedef FluxBehaviorProcessorLoadBaselinesC = Int32 Function(
    Pointer<Void> processor, Pointer<Utf8> json);
typedef FluxBehaviorProcessorLoadBaselinesDart = int Function(
    Pointer<Void> processor, Pointer<Utf8> json);

typedef FluxFreeStringC = Void Function(Pointer<Utf8> s);
typedef FluxFreeStringDart = void Function(Pointer<Utf8> s);

/// Bridge to synheart-flux Rust library.
class FluxBridge {
  static FluxBridge? _instance;
  DynamicLibrary? _lib;
  bool _initialized = false;

  // FFI function pointers
  FluxBehaviorToHsiDart? _behaviorToHsi;
  FluxBehaviorProcessorNewDart? _processorNew;
  FluxBehaviorProcessorFreeDart? _processorFree;
  FluxBehaviorProcessorProcessDart? _processorProcess;
  FluxBehaviorProcessorSaveBaselinesDart? _processorSaveBaselines;
  FluxBehaviorProcessorLoadBaselinesDart? _processorLoadBaselines;
  FluxFreeStringDart? _freeString;

  FluxBridge._();

  /// Get the singleton instance of FluxBridge.
  static FluxBridge get instance {
    _instance ??= FluxBridge._();
    return _instance!;
  }

  /// Initialize the FFI bridge by loading the native library.
  ///
  /// Returns true if initialization succeeded, false otherwise.
  bool initialize() {
    if (_initialized) return true;

    try {
      _lib = _loadLibrary();
      if (_lib == null) {
        print('FluxBridge: Failed to load native library');
        return false;
      }

      _behaviorToHsi = _lib!
          .lookup<NativeFunction<FluxBehaviorToHsiC>>('flux_behavior_to_hsi')
          .asFunction();

      _processorNew = _lib!
          .lookup<NativeFunction<FluxBehaviorProcessorNewC>>(
              'flux_behavior_processor_new')
          .asFunction();

      _processorFree = _lib!
          .lookup<NativeFunction<FluxBehaviorProcessorFreeC>>(
              'flux_behavior_processor_free')
          .asFunction();

      _processorProcess = _lib!
          .lookup<NativeFunction<FluxBehaviorProcessorProcessC>>(
              'flux_behavior_processor_process')
          .asFunction();

      _processorSaveBaselines = _lib!
          .lookup<NativeFunction<FluxBehaviorProcessorSaveBaselinesC>>(
              'flux_behavior_processor_save_baselines')
          .asFunction();

      _processorLoadBaselines = _lib!
          .lookup<NativeFunction<FluxBehaviorProcessorLoadBaselinesC>>(
              'flux_behavior_processor_load_baselines')
          .asFunction();

      _freeString = _lib!
          .lookup<NativeFunction<FluxFreeStringC>>('flux_free_string')
          .asFunction();

      _initialized = true;
      print('FluxBridge: Successfully initialized');
      return true;
    } catch (e) {
      print('FluxBridge: Initialization failed: $e');
      return false;
    }
  }

  /// Load the native library based on platform.
  DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libsynheart_flux.so');
      } else if (Platform.isIOS) {
        return DynamicLibrary.process();
      } else if (Platform.isMacOS) {
        // For macOS desktop or development
        return DynamicLibrary.open('libsynheart_flux.dylib');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libsynheart_flux.so');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('synheart_flux.dll');
      }
    } catch (e) {
      print('FluxBridge: Failed to load library: $e');
    }
    return null;
  }

  /// Check if the bridge is initialized and ready to use.
  bool get isInitialized => _initialized;

  /// Convert behavioral session to HSI JSON (stateless, one-shot).
  ///
  /// [sessionJson] should be a JSON string containing the behavioral session data
  /// in the format expected by synheart-flux.
  ///
  /// Returns the HSI JSON string, or null if computation failed.
  String? behaviorToHsi(String sessionJson) {
    if (!_initialized || _behaviorToHsi == null) {
      print('FluxBridge: Not initialized');
      return null;
    }

    final jsonPtr = sessionJson.toNativeUtf8();
    try {
      final resultPtr = _behaviorToHsi!(jsonPtr);
      if (resultPtr == nullptr) {
        return null;
      }

      final result = resultPtr.toDartString();
      _freeString?.call(resultPtr);
      return result;
    } finally {
      calloc.free(jsonPtr);
    }
  }

  /// Parse HSI JSON into a Dart Map.
  Map<String, dynamic>? parseHsiJson(String? hsiJson) {
    if (hsiJson == null) return null;
    try {
      return jsonDecode(hsiJson) as Map<String, dynamic>;
    } catch (e) {
      print('FluxBridge: Failed to parse HSI JSON: $e');
      return null;
    }
  }
}

/// Stateful behavioral processor with persistent baselines.
///
/// Use this class when you want baselines to accumulate across multiple sessions.
class FluxBehaviorProcessor {
  final FluxBridge _bridge;
  Pointer<Void>? _processor;
  bool _disposed = false;

  /// Create a new behavioral processor with the specified baseline window.
  ///
  /// [baselineWindowSessions] is the number of sessions to include in the
  /// rolling baseline (default: 20).
  FluxBehaviorProcessor({int baselineWindowSessions = 20})
      : _bridge = FluxBridge.instance {
    if (!_bridge.isInitialized) {
      if (!_bridge.initialize()) {
        throw Exception('Failed to initialize FluxBridge');
      }
    }

    _processor = _bridge._processorNew?.call(baselineWindowSessions);
    if (_processor == null || _processor == nullptr) {
      throw Exception('Failed to create BehaviorProcessor');
    }
  }

  /// Process a behavioral session and return HSI JSON.
  ///
  /// This updates the internal baselines and returns HSI-compliant JSON.
  String? process(String sessionJson) {
    if (_disposed || _processor == null || _processor == nullptr) {
      print('FluxBehaviorProcessor: Processor is disposed or invalid');
      return null;
    }

    final jsonPtr = sessionJson.toNativeUtf8();
    try {
      final resultPtr = _bridge._processorProcess?.call(_processor!, jsonPtr);
      if (resultPtr == null || resultPtr == nullptr) {
        return null;
      }

      final result = resultPtr.toDartString();
      _bridge._freeString?.call(resultPtr);
      return result;
    } finally {
      calloc.free(jsonPtr);
    }
  }

  /// Save current baselines to JSON for persistence.
  String? saveBaselines() {
    if (_disposed || _processor == null || _processor == nullptr) {
      return null;
    }

    final resultPtr = _bridge._processorSaveBaselines?.call(_processor!);
    if (resultPtr == null || resultPtr == nullptr) {
      return null;
    }

    final result = resultPtr.toDartString();
    _bridge._freeString?.call(resultPtr);
    return result;
  }

  /// Load baselines from JSON.
  ///
  /// Returns true if loading succeeded, false otherwise.
  bool loadBaselines(String baselinesJson) {
    if (_disposed || _processor == null || _processor == nullptr) {
      return false;
    }

    final jsonPtr = baselinesJson.toNativeUtf8();
    try {
      final result =
          _bridge._processorLoadBaselines?.call(_processor!, jsonPtr);
      return result == 0;
    } finally {
      calloc.free(jsonPtr);
    }
  }

  /// Dispose the processor and free native resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    if (_processor != null && _processor != nullptr) {
      _bridge._processorFree?.call(_processor!);
      _processor = null;
    }
  }
}

/// Convert native session data to synheart-flux session JSON format.
///
/// This helper converts the event format used by the native SDK to the
/// format expected by synheart-flux.
String convertSessionToFluxJson({
  required String sessionId,
  required String deviceId,
  required String timezone,
  required DateTime startTime,
  required DateTime endTime,
  required List<Map<String, dynamic>> events,
}) {
  final fluxEvents = events.map((event) {
    final eventType =
        event['event_type'] as String? ?? event['type'] as String?;
    final timestamp = event['timestamp'];
    final metrics = event['metrics'] as Map<String, dynamic>? ??
        event['payload'] as Map<String, dynamic>? ??
        {};

    final fluxEvent = <String, dynamic>{
      'timestamp': timestamp is String
          ? timestamp
          : DateTime.fromMillisecondsSinceEpoch(timestamp as int)
              .toUtc()
              .toIso8601String(),
      'event_type': eventType,
    };

    // Map event-specific data
    switch (eventType) {
      case 'scroll':
        final scroll = <String, dynamic>{
          'velocity': metrics['velocity'] ?? 0.0,
          'direction': metrics['direction'] ?? 'down',
        };
        // Include direction_reversal if available (Flux accepts this field)
        if (metrics.containsKey('direction_reversal')) {
          scroll['direction_reversal'] = metrics['direction_reversal'] ?? false;
        }
        fluxEvent['scroll'] = scroll;
        break;
      case 'tap':
        fluxEvent['tap'] = {
          'tap_duration_ms': metrics['tap_duration_ms'] ?? 0,
          'long_press': metrics['long_press'] ?? false,
        };
        break;
      case 'swipe':
        fluxEvent['swipe'] = {
          'velocity': metrics['velocity'] ?? 0.0,
          'direction': metrics['direction'] ?? 'unknown',
        };
        break;
      case 'notification':
        final interruption = <String, dynamic>{
          'action': metrics['action'] ?? 'ignored',
        };
        // Include source_app_id if available (Flux accepts this field)
        if (metrics.containsKey('source_app_id')) {
          interruption['source_app_id'] = metrics['source_app_id'];
        }
        fluxEvent['interruption'] = interruption;
        break;
      case 'call':
        final interruption = <String, dynamic>{
          'action': metrics['action'] ?? 'ignored',
        };
        // Include source_app_id if available (Flux accepts this field)
        if (metrics.containsKey('source_app_id')) {
          interruption['source_app_id'] = metrics['source_app_id'];
        }
        fluxEvent['interruption'] = interruption;
        break;
      case 'typing':
        final typing = <String, dynamic>{
          'typing_speed_cpm': metrics['typing_speed'] ?? 0.0,
          'cadence_stability': metrics['typing_cadence_stability'] ?? 0.0,
        };
        // Include duration_sec if available (Flux accepts this field)
        if (metrics.containsKey('duration')) {
          final duration = metrics['duration'];
          typing['duration_sec'] = duration is num
              ? duration.toDouble()
              : (double.tryParse(duration.toString()) ?? 0.0);
        }
        // Include pause_count if available (Flux accepts this field)
        // Map typing_gap_count to pause_count as they represent the same concept
        final pauseCount =
            metrics['pause_count'] ?? metrics['typing_gap_count'];
        if (pauseCount != null) {
          typing['pause_count'] = pauseCount is num
              ? pauseCount.toInt()
              : (int.tryParse(pauseCount.toString()) ?? 0);
        }
        // Include detailed typing metrics that Flux uses for aggregation
        // These are needed for Flux to calculate average_keystrokes_per_session,
        // average_typing_gap, average_inter_tap_interval, and burstiness_of_typing
        if (metrics.containsKey('typing_tap_count')) {
          final tapCount = metrics['typing_tap_count'];
          typing['typing_tap_count'] = tapCount is num
              ? tapCount.toInt()
              : (int.tryParse(tapCount.toString()) ?? 0);
        }
        if (metrics.containsKey('mean_inter_tap_interval_ms')) {
          final iti = metrics['mean_inter_tap_interval_ms'];
          typing['mean_inter_tap_interval_ms'] = iti is num
              ? iti.toDouble()
              : (double.tryParse(iti.toString()) ?? 0.0);
        }
        if (metrics.containsKey('typing_burstiness')) {
          final burst = metrics['typing_burstiness'];
          typing['typing_burstiness'] = burst is num
              ? burst.toDouble()
              : (double.tryParse(burst.toString()) ?? 0.0);
        }
        // Include session boundaries if available
        if (metrics.containsKey('start_at')) {
          typing['start_at'] = metrics['start_at'].toString();
        }
        if (metrics.containsKey('end_at')) {
          typing['end_at'] = metrics['end_at'].toString();
        }
        fluxEvent['typing'] = typing;
        break;
      case 'app_switch':
        fluxEvent['app_switch'] = {
          'from_app_id': metrics['from_app_id'] ?? '',
          'to_app_id': metrics['to_app_id'] ?? '',
        };
        break;
    }

    return fluxEvent;
  }).toList();

  final session = {
    'session_id': sessionId,
    'device_id': deviceId,
    'timezone': timezone,
    'start_time': startTime.toUtc().toIso8601String(),
    'end_time': endTime.toUtc().toIso8601String(),
    'events': fluxEvents,
  };

  return jsonEncode(session);
}

/// Extract behavioral metrics from HSI JSON response.
///
/// This helper extracts the behavioral metrics in a format compatible
/// with the existing SDK output format.
/// Uses HSI 1.0 format: axes.behavior.readings array
Map<String, dynamic>? extractBehavioralMetrics(Map<String, dynamic>? hsi) {
  if (hsi == null) return null;

  try {
    // HSI 1.0 format: axes.behavior.readings array
    final axes = hsi['axes'] as Map<String, dynamic>?;
    if (axes == null) return null;

    final behavior = axes['behavior'] as Map<String, dynamic>?;
    if (behavior == null) return null;

    final readings = behavior['readings'] as List<dynamic>?;
    if (readings == null || readings.isEmpty) return null;

    // Extract metrics from axis readings
    final metricsMap = <String, double>{};
    for (final reading in readings) {
      if (reading is Map<String, dynamic>) {
        final axis = reading['axis'] as String? ?? '';
        final score = reading['score'];
        if (score is num) {
          metricsMap[axis] = score.toDouble();
        }
      }
    }

    // Extract meta information
    final meta = hsi['meta'] as Map<String, dynamic>?;

    // Build result map with SDK-expected field names
    final result = <String, dynamic>{
      'interaction_intensity': metricsMap['interaction_intensity'] ?? 0.0,
      'task_switch_rate': metricsMap['task_switch_rate'] ?? 0.0,
      'task_switch_cost': 0, // Not in HSI format, keep as 0
      'idle_time_ratio': metricsMap['idle_ratio'] ?? 0.0,
      'active_time_ratio': 1.0 - (metricsMap['idle_ratio'] ?? 0.0),
      'notification_load': metricsMap['notification_load'] ?? 0.0,
      'burstiness': metricsMap['burstiness'] ?? 0.0,
      'behavioral_distraction_score': metricsMap['distraction'] ?? 0.0,
      'focus_hint': metricsMap['focus'] ?? 0.0,
      'fragmented_idle_ratio': metricsMap['fragmented_idle_ratio'] ?? 0.0,
      'scroll_jitter_rate': metricsMap['scroll_jitter_rate'] ?? 0.0,
      'deep_focus_blocks': (meta?['deep_focus_blocks'] as num?)?.toInt() ?? 0,
      'sessions_in_baseline':
          (meta?['sessions_in_baseline'] as num?)?.toInt() ?? 0,
    };

    // Add baseline info from meta if available
    if (meta != null) {
      final baselineDistraction = meta['baseline_distraction'];
      if (baselineDistraction is num) {
        result['baseline_distraction'] = baselineDistraction.toDouble();
      }
      final baselineFocus = meta['baseline_focus'];
      if (baselineFocus is num) {
        result['baseline_focus'] = baselineFocus.toDouble();
      }
      final distractionDeviationPct = meta['distraction_deviation_pct'];
      if (distractionDeviationPct is num) {
        result['distraction_deviation_pct'] =
            distractionDeviationPct.toDouble();
      }
    }

    return result;
  } catch (e) {
    print('FluxBridge: Failed to extract behavioral metrics: $e');
    rethrow;
  }
}
