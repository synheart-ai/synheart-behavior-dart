import Foundation

/// Bridge to synheart-flux Rust library for behavioral metrics computation.
///
/// This class provides C FFI bindings to the Rust implementation of behavioral metrics,
/// ensuring consistent HSI-compliant output across all platforms.
public class FluxBridge {

    public static let shared = FluxBridge()

    private var initialized = false

    private init() {
        // Check if the Rust library is available by trying to call a function
        // The library should be statically linked in the XCFramework
        initialized = checkRustLibraryAvailable()
        if initialized {
            print("FluxBridge: Successfully initialized Rust library")
        } else {
            print("FluxBridge: Rust library not available, using Swift fallback")
        }
    }

    private func checkRustLibraryAvailable() -> Bool {
        // Try to get a symbol from the library to verify it's loaded
        // The library should be statically linked, so we check if the symbol exists
        #if SYNHEART_FLUX_ENABLED
        return true
        #else
        // Check if the function symbol is available
        let handle = dlopen(nil, RTLD_NOW)
        let symbol = dlsym(handle, "flux_behavior_to_hsi")
        return symbol != nil
        #endif
    }

    /// Check if the Rust library is available.
    public var isAvailable: Bool {
        return initialized
    }

    /// Convert behavioral session to HSI JSON (stateless, one-shot).
    ///
    /// - Parameter sessionJson: JSON string containing the behavioral session data
    /// - Returns: HSI JSON string, or nil if computation failed
    public func behaviorToHsi(_ sessionJson: String) -> String? {
        guard initialized else {
            print("FluxBridge: Rust library not initialized")
            return nil
        }

        guard let jsonCString = sessionJson.cString(using: .utf8) else {
            print("FluxBridge: Failed to convert session JSON to C string")
            return nil
        }

        // Call the Rust function
        guard let resultPtr = flux_behavior_to_hsi(jsonCString) else {
            print("FluxBridge: flux_behavior_to_hsi returned null")
            return nil
        }

        let result = String(cString: resultPtr)
        flux_free_string(resultPtr)
        return result
    }

    /// Create a stateful behavioral processor with the specified baseline window.
    ///
    /// - Parameter baselineWindowSessions: Number of sessions in the rolling baseline
    /// - Returns: Processor handle, or nil if creation failed
    public func createProcessor(baselineWindowSessions: Int = 20) -> OpaquePointer? {
        guard initialized else { return nil }
        return flux_behavior_processor_new(Int32(baselineWindowSessions))
    }

    /// Free a processor created with createProcessor.
    public func freeProcessor(_ handle: OpaquePointer) {
        guard initialized else { return }
        flux_behavior_processor_free(handle)
    }

    /// Process a behavioral session with the stateful processor.
    ///
    /// - Parameters:
    ///   - handle: Processor handle from createProcessor
    ///   - sessionJson: JSON string containing the behavioral session data
    /// - Returns: HSI JSON string, or nil if computation failed
    public func processSession(_ handle: OpaquePointer, sessionJson: String) -> String? {
        guard initialized else { return nil }

        guard let jsonCString = sessionJson.cString(using: .utf8) else {
            return nil
        }

        guard let resultPtr = flux_behavior_processor_process(handle, jsonCString) else {
            return nil
        }

        let result = String(cString: resultPtr)
        flux_free_string(resultPtr)
        return result
    }

    /// Save baselines from a processor to JSON for persistence.
    public func saveBaselines(_ handle: OpaquePointer) -> String? {
        guard initialized else { return nil }

        guard let resultPtr = flux_behavior_processor_save_baselines(handle) else {
            return nil
        }

        let result = String(cString: resultPtr)
        flux_free_string(resultPtr)
        return result
    }

    /// Load baselines into a processor from JSON.
    ///
    /// - Returns: true if loading succeeded, false otherwise
    public func loadBaselines(_ handle: OpaquePointer, baselinesJson: String) -> Bool {
        guard initialized else { return false }

        guard let jsonCString = baselinesJson.cString(using: .utf8) else {
            return false
        }

        return flux_behavior_processor_load_baselines(handle, jsonCString) == 0
    }
}

// MARK: - C FFI Declarations

// These functions are provided by the synheart-flux static library
// When the library is not available, these will fail at link time or return nil

@_silgen_name("flux_behavior_to_hsi")
private func flux_behavior_to_hsi(_ json: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("flux_free_string")
private func flux_free_string(_ s: UnsafeMutablePointer<CChar>?)

@_silgen_name("flux_behavior_processor_new")
private func flux_behavior_processor_new(_ baselineWindowSessions: Int32) -> OpaquePointer?

@_silgen_name("flux_behavior_processor_free")
private func flux_behavior_processor_free(_ processor: OpaquePointer?)

@_silgen_name("flux_behavior_processor_process")
private func flux_behavior_processor_process(_ processor: OpaquePointer?, _ json: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("flux_behavior_processor_save_baselines")
private func flux_behavior_processor_save_baselines(_ processor: OpaquePointer?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("flux_behavior_processor_load_baselines")
private func flux_behavior_processor_load_baselines(_ processor: OpaquePointer?, _ json: UnsafePointer<CChar>?) -> Int32

// MARK: - Helper Functions

/// Convert session events to synheart-flux JSON format.
/// Events should have: timestamp (String), eventType (String), metrics ([String: Any])
public func convertEventsToFluxJson(
    sessionId: String,
    deviceId: String,
    timezone: String,
    startTime: Date,
    endTime: Date,
    events: [(timestamp: String, eventType: String, metrics: [String: Any])]
) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var fluxEvents: [[String: Any]] = []

    for event in events {
        var fluxEvent: [String: Any] = [
            "timestamp": event.timestamp,
            "event_type": event.eventType
        ]

        switch event.eventType {
        case "scroll":
            fluxEvent["scroll"] = [
                "velocity": event.metrics["velocity"] ?? 0.0,
                "direction": event.metrics["direction"] ?? "down"
            ]
        case "tap":
            fluxEvent["tap"] = [
                "tap_duration_ms": event.metrics["tap_duration_ms"] ?? 0,
                "long_press": event.metrics["long_press"] ?? false
            ]
        case "swipe":
            fluxEvent["swipe"] = [
                "velocity": event.metrics["velocity"] ?? 0.0,
                "direction": event.metrics["direction"] ?? "unknown"
            ]
        case "notification", "call":
            fluxEvent["interruption"] = [
                "action": event.metrics["action"] ?? "ignored"
            ]
        case "typing":
            fluxEvent["typing"] = [
                "typing_speed_cpm": event.metrics["typing_speed"] ?? 0.0,
                "cadence_stability": event.metrics["typing_cadence_stability"] ?? 0.0
            ]
        case "app_switch":
            fluxEvent["app_switch"] = [
                "from_app_id": event.metrics["from_app_id"] ?? "",
                "to_app_id": event.metrics["to_app_id"] ?? ""
            ]
        default:
            break
        }

        fluxEvents.append(fluxEvent)
    }

    let session: [String: Any] = [
        "session_id": sessionId,
        "device_id": deviceId,
        "timezone": timezone,
        "start_time": formatter.string(from: startTime),
        "end_time": formatter.string(from: endTime),
        "events": fluxEvents
    ]

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: session)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    } catch {
        print("FluxBridge: Failed to serialize session to JSON: \(error)")
        return "{}"
    }
}

/// Extract behavioral metrics from HSI JSON in the format expected by the SDK.
public func extractBehavioralMetricsFromHsi(_ hsiJson: String) -> [String: Any]? {
    guard let data = hsiJson.data(using: .utf8),
          let hsi = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let behaviorWindows = hsi["behavior_windows"] as? [[String: Any]],
          let window = behaviorWindows.first,
          let behavior = window["behavior"] as? [String: Any] else {
        return nil
    }

    let baseline = window["baseline"] as? [String: Any]
    _ = window["event_summary"] as? [String: Any] // Available for future use

    var metrics: [String: Any] = [
        "interaction_intensity": behavior["interaction_intensity"] ?? 0.0,
        "task_switch_rate": behavior["task_switch_rate"] ?? 0.0,
        "task_switch_cost": 0,
        "idle_time_ratio": behavior["idle_ratio"] ?? 0.0,
        "active_time_ratio": 1.0 - ((behavior["idle_ratio"] as? Double) ?? 0.0),
        "notification_load": behavior["notification_load"] ?? 0.0,
        "burstiness": behavior["burstiness"] ?? 0.0,
        "behavioral_distraction_score": behavior["distraction_score"] ?? 0.0,
        "focus_hint": behavior["focus_hint"] ?? 0.0,
        "fragmented_idle_ratio": behavior["fragmented_idle_ratio"] ?? 0.0,
        "scroll_jitter_rate": behavior["scroll_jitter_rate"] ?? 0.0,
        "deep_focus_blocks": extractDeepFocusBlocks(behavior["deep_focus_blocks"]),
        "sessions_in_baseline": baseline?["sessions_in_baseline"] ?? 0
    ]

    // Add baseline info if available
    if let baseline = baseline {
        if let distractionBaseline = baseline["distraction"] as? Double {
            metrics["baseline_distraction"] = distractionBaseline
        }
        if let focusBaseline = baseline["focus"] as? Double {
            metrics["baseline_focus"] = focusBaseline
        }
        if let deviationPct = baseline["distraction_deviation_pct"] as? Double {
            metrics["distraction_deviation_pct"] = deviationPct
        }
    }

    return metrics
}

private func extractDeepFocusBlocks(_ blocks: Any?) -> [[String: Any]] {
    guard let blocksArray = blocks as? [[String: Any]] else {
        // If it's a number (count), return empty array
        return []
    }
    return blocksArray.map { block in
        [
            "start_at": block["start_at"] ?? "",
            "end_at": block["end_at"] ?? "",
            "duration_ms": block["duration_ms"] ?? 0
        ]
    }
}
