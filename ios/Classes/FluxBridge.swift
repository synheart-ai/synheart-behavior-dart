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
        // For statically linked libraries, if the build succeeds, the symbols are linked
        // Try to call flux_version() to verify at runtime
        // If the function exists (we got here without linker errors), try calling it
        print("FluxBridge: Checking library availability...")
        let versionPtr = flux_version()
        if let versionPtr = versionPtr {
            let version = String(cString: versionPtr)
            print("FluxBridge: ✅ Found synheart-flux version: \(version)")
            return !version.isEmpty
        }
        // If version is nil, try to see if we can at least call the function pointer
        // For static libraries, if we got here without linker errors, the symbols should be available
        // The real test will be when we try to call flux_behavior_to_hsi
        print("FluxBridge: ⚠️ flux_version() returned nil, but symbols are linked (statically linked)")
        print("FluxBridge: Will attempt to use library - availability will be confirmed on first use")
        return true
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
            // Check for error message
            if let errorPtr = flux_last_error() {
                let errorMsg = String(cString: errorPtr)
                print("FluxBridge: Error from Rust: \(errorMsg)")
            }
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
// The library is statically linked via the XCFramework

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

@_silgen_name("flux_version")
private func flux_version() -> UnsafePointer<CChar>?

@_silgen_name("flux_last_error")
private func flux_last_error() -> UnsafePointer<CChar>?

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
    
    // DEBUG: Count scroll events being sent to Flux
    var scrollEventCount = 0
    var scrollEventsWithReversal = 0
    var scrollEventsWithoutReversal = 0
    var scrollEventsWithoutScrollData = 0

    for event in events {
        var fluxEvent: [String: Any] = [
            "timestamp": event.timestamp,
            "event_type": event.eventType
        ]

        switch event.eventType {
        case "scroll":
            scrollEventCount += 1
            let hasReversal = event.metrics["direction_reversal"] as? Bool ?? false
            let hasScrollData = event.metrics["direction_reversal"] != nil
            
            if hasScrollData {
                if hasReversal {
                    scrollEventsWithReversal += 1
                } else {
                    scrollEventsWithoutReversal += 1
                }
            } else {
                scrollEventsWithoutScrollData += 1
            }
            
            var scroll: [String: Any] = [
                "velocity": event.metrics["velocity"] ?? 0.0,
                "direction": event.metrics["direction"] ?? "down"
            ]
            // Include direction_reversal if available (Flux accepts this field)
            if let directionReversal = event.metrics["direction_reversal"] as? Bool {
                scroll["direction_reversal"] = directionReversal
            }
            fluxEvent["scroll"] = scroll
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
            var interruption: [String: Any] = [
                "action": event.metrics["action"] ?? "ignored"
            ]
            // Include source_app_id if available (Flux accepts this field)
            if let sourceAppId = event.metrics["source_app_id"] {
                interruption["source_app_id"] = sourceAppId
            }
            fluxEvent["interruption"] = interruption
        case "typing":
            var typing: [String: Any] = [
                "typing_speed_cpm": event.metrics["typing_speed"] ?? 0.0,
                "cadence_stability": event.metrics["typing_cadence_stability"] ?? 0.0
            ]
            // Include duration_sec if available (Flux accepts this field)
            if let duration = event.metrics["duration"] {
                let durationSec: Double
                if let num = duration as? NSNumber {
                    durationSec = num.doubleValue
                } else if let str = duration as? String, let val = Double(str) {
                    durationSec = val
                } else {
                    durationSec = 0.0
                }
                typing["duration_sec"] = durationSec
            }
            // Include pause_count if available (Flux accepts this field)
            // Map typing_gap_count to pause_count as they represent the same concept
            if let pauseCount = event.metrics["pause_count"] ?? event.metrics["typing_gap_count"] {
                let pauseCountValue: Int
                if let num = pauseCount as? NSNumber {
                    pauseCountValue = num.intValue
                } else if let str = pauseCount as? String, let val = Int(str) {
                    pauseCountValue = val
                } else {
                    pauseCountValue = 0
                }
                typing["pause_count"] = pauseCountValue
            }
            // Include detailed typing metrics that Flux uses for aggregation
            // These are needed for Flux to calculate average_keystrokes_per_session,
            // average_typing_gap, average_inter_tap_interval, and burstiness_of_typing
            if let typingTapCount = event.metrics["typing_tap_count"] {
                let tapCountValue: Int
                if let num = typingTapCount as? NSNumber {
                    tapCountValue = num.intValue
                } else if let str = typingTapCount as? String, let val = Int(str) {
                    tapCountValue = val
                } else {
                    tapCountValue = 0
                }
                typing["typing_tap_count"] = tapCountValue
            }
            if let meanInterTapInterval = event.metrics["mean_inter_tap_interval_ms"] {
                let itiValue: Double
                if let num = meanInterTapInterval as? NSNumber {
                    itiValue = num.doubleValue
                } else if let str = meanInterTapInterval as? String, let val = Double(str) {
                    itiValue = val
                } else {
                    itiValue = 0.0
                }
                typing["mean_inter_tap_interval_ms"] = itiValue
            }
            if let typingBurstiness = event.metrics["typing_burstiness"] {
                let burstValue: Double
                if let num = typingBurstiness as? NSNumber {
                    burstValue = num.doubleValue
                } else if let str = typingBurstiness as? String, let val = Double(str) {
                    burstValue = val
                } else {
                    burstValue = 0.0
                }
                typing["typing_burstiness"] = burstValue
            }
            // Include session boundaries if available
            if let startAt = event.metrics["start_at"] {
                typing["start_at"] = startAt
            }
            if let endAt = event.metrics["end_at"] {
                typing["end_at"] = endAt
            }
            // Correction and clipboard counts for Flux (correction_rate, clipboard_activity_rate)
            if let backspaceCount = event.metrics["backspace_count"] {
                typing["number_of_backspace"] = (backspaceCount as? NSNumber)?.intValue ?? (backspaceCount as? String).flatMap { Int($0) } ?? 0
            } else {
                typing["number_of_backspace"] = 0
            }
            typing["number_of_delete"] = 0
            typing["number_of_copy"] = (event.metrics["number_of_copy"] as? NSNumber)?.intValue ?? (event.metrics["number_of_copy"] as? String).flatMap { Int($0) } ?? 0
            typing["number_of_paste"] = (event.metrics["number_of_paste"] as? NSNumber)?.intValue ?? (event.metrics["number_of_paste"] as? String).flatMap { Int($0) } ?? 0
            typing["number_of_cut"] = (event.metrics["number_of_cut"] as? NSNumber)?.intValue ?? (event.metrics["number_of_cut"] as? String).flatMap { Int($0) } ?? 0
            fluxEvent["typing"] = typing
        case "app_switch":
            fluxEvent["app_switch"] = [
                "from_app_id": event.metrics["from_app_id"] ?? "",
                "to_app_id": event.metrics["to_app_id"] ?? ""
            ]
        case "clipboard":
            // Clipboard events are tracked separately, not sent to Flux
            // Skip this event in Flux JSON conversion
            continue
        default:
            break
        }

        fluxEvents.append(fluxEvent)
    }
    
    // DEBUG: Log what we're sending to Flux
    print("FluxBridge: === CONVERTING TO FLUX JSON ===")
    print("FluxBridge: Total scroll events being sent: \(scrollEventCount)")
    print("FluxBridge:   - With reversal=true: \(scrollEventsWithReversal)")
    print("FluxBridge:   - With reversal=false: \(scrollEventsWithoutReversal)")
    print("FluxBridge:   - Without direction_reversal field: \(scrollEventsWithoutScrollData)")
    print("FluxBridge: === END CONVERSION DEBUG ===")

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
          let hsi = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("FluxBridge: Failed to parse HSI JSON")
        return nil
    }
    
    // HSI 1.0 format: axes.behavior.readings array
    guard let axes = hsi["axes"] as? [String: Any],
          let behavior = axes["behavior"] as? [String: Any],
          let readings = behavior["readings"] as? [[String: Any]] else {
        print("FluxBridge: HSI JSON missing axes.behavior.readings structure")
        // Try to print the structure for debugging
        if let axes = hsi["axes"] as? [String: Any] {
            print("FluxBridge: axes keys: \(Array(axes.keys))")
        }
        return nil
    }

    // Extract metrics from axis readings
    var metricsMap: [String: Double] = [:]
    for reading in readings {
        if let axis = reading["axis"] as? String,
           let score = reading["score"] as? Double {
            metricsMap[axis] = score
        }
    }
    
    // Extract meta information
    let meta = hsi["meta"] as? [String: Any]
    
    // DEBUG: Log scroll jitter rate from Flux
    let scrollJitterFromFlux = metricsMap["scroll_jitter_rate"] ?? 0.0
    print("FluxBridge: === FLUX SCROLL JITTER DEBUG ===")
    print("FluxBridge: Scroll jitter rate from Flux: \(scrollJitterFromFlux)")
    
    // Try to extract meta info for scroll events count
    let totalEvents = meta?["total_events"] as? Int ?? -1
    print("FluxBridge: Total events in Flux meta: \(totalEvents)")
    print("FluxBridge: === END FLUX SCROLL JITTER DEBUG ===")
    
    // DEBUG: Log deep focus blocks information
    print("FluxBridge: === FLUX DEEP FOCUS BLOCKS DEBUG ===")
    let deepFocusBlocksCount = meta?["deep_focus_blocks"] as? Int ?? 0
    print("FluxBridge: Deep focus blocks count from Flux: \(deepFocusBlocksCount)")
    
    // Log session duration
    let sessionDurationSec = meta?["duration_sec"] as? Double ?? 0.0
    print("FluxBridge: Session duration (seconds): \(sessionDurationSec)")
    
    // Log deep focus blocks detail if available
    if let deepFocusDetail = meta?["deep_focus_blocks_detail"] as? [[String: Any]] {
        if !deepFocusDetail.isEmpty {
            print("FluxBridge: Deep focus blocks detail found: \(deepFocusDetail.count) blocks")
            for (index, block) in deepFocusDetail.enumerated() {
                let startAt = block["start_at"] as? String ?? ""
                let endAt = block["end_at"] as? String ?? ""
                let durationMs = block["duration_ms"] as? Int ?? 0
                let durationSec = Double(durationMs) / 1000.0
                print("FluxBridge:   Block[\(index)]: start=\(startAt), end=\(endAt), duration=\(durationMs)ms (\(durationSec)s)")
            }
        } else {
            print("FluxBridge: Deep focus blocks detail array is empty")
        }
    } else {
        print("FluxBridge: No deep focus blocks detail found in meta")
        print("FluxBridge: This means no engagement segments >= 120 seconds were detected")
    }
    
    // Log all meta keys for debugging
    if let meta = meta {
        let metaKeys = Array(meta.keys)
        print("FluxBridge: Available meta keys: \(metaKeys.joined(separator: ", "))")
    }
    
    print("FluxBridge: === END FLUX DEEP FOCUS BLOCKS DEBUG ===")
    
        // Build result map with SDK-expected field names
        // Flux outputs task_switch_cost as normalized 0-1 in HSI, but SDK expects raw ms
        // Convert normalized back to raw ms for SDK compatibility: normalized * 10000
        let taskSwitchCostNormalized = metricsMap["task_switch_cost"] ?? 0.0
        let taskSwitchCostMs = Int(taskSwitchCostNormalized * 10000.0)

    var metrics: [String: Any] = [
            "interaction_intensity": metricsMap["interaction_intensity"] ?? 0.0,
            "task_switch_rate": metricsMap["task_switch_rate"] ?? 0.0,
            "task_switch_cost": taskSwitchCostMs,
            "idle_time_ratio": metricsMap["idle_ratio"] ?? 0.0,
            // Flux outputs active_time_ratio directly in HSI readings
            "active_time_ratio": metricsMap["active_time_ratio"] ?? (1.0 - (metricsMap["idle_ratio"] ?? 0.0)),
        "notification_load": metricsMap["notification_load"] ?? 0.0,
        "burstiness": metricsMap["burstiness"] ?? 0.0,
        "behavioral_distraction_score": metricsMap["distraction"] ?? 0.0,
        "focus_hint": metricsMap["focus"] ?? 0.0,
        "fragmented_idle_ratio": metricsMap["fragmented_idle_ratio"] ?? 0.0,
        "scroll_jitter_rate": metricsMap["scroll_jitter_rate"] ?? 0.0,
        // Extract deep focus blocks detail as a List (matching Swift's format)
        // Swift returns [[String: Any]], so we need to match that format
        "deep_focus_blocks": extractDeepFocusBlocks(meta?["deep_focus_blocks_detail"] as? [[String: Any]]),
        "sessions_in_baseline": meta?["sessions_in_baseline"] as? Int ?? 0
    ]

    // Add baseline info from meta if available
    if let meta = meta {
        if let distractionBaseline = meta["baseline_distraction"] as? Double {
            metrics["baseline_distraction"] = distractionBaseline
        }
        if let focusBaseline = meta["baseline_focus"] as? Double {
            metrics["baseline_focus"] = focusBaseline
        }
        if let deviationPct = meta["distraction_deviation_pct"] as? Double {
            metrics["distraction_deviation_pct"] = deviationPct
        }
        
        // Extract typing session summary from Flux's meta
        let typingSummary = extractTypingSessionSummary(meta)
        if !typingSummary.isEmpty {
            metrics["typing_session_summary"] = typingSummary
        }
    }

    return metrics
}

/// Extract deep focus blocks from Flux's deep_focus_blocks_detail array
private func extractDeepFocusBlocks(_ blocks: [[String: Any]]?) -> [[String: Any]] {
    guard let blocks = blocks else { return [] }
    return blocks.map { block in
        [
            "start_at": block["start_at"] as? String ?? "",
            "end_at": block["end_at"] as? String ?? "",
            "duration_ms": block["duration_ms"] as? Int ?? 0
        ]
    }
}

/// Extract typing session summary from Flux's meta section.
private func extractTypingSessionSummary(_ meta: [String: Any]) -> [String: Any] {
    return [
        "typing_session_count": meta["typing_session_count"] as? Int ?? 0,
        "average_keystrokes_per_session": meta["average_keystrokes_per_session"] as? Double ?? 0.0,
        "average_typing_session_duration": meta["average_typing_session_duration"] as? Double ?? 0.0,
        "average_typing_speed": meta["average_typing_speed"] as? Double ?? 0.0,
        "average_typing_gap": meta["average_typing_gap"] as? Double ?? 0.0,
        "average_inter_tap_interval": meta["average_inter_tap_interval"] as? Double ?? 0.0,
        "typing_cadence_stability": meta["typing_cadence_stability"] as? Double ?? 0.0,
        "burstiness_of_typing": meta["burstiness_of_typing"] as? Double ?? 0.0,
        "total_typing_duration": meta["total_typing_duration"] as? Int ?? 0,
        "active_typing_ratio": meta["active_typing_ratio"] as? Double ?? 0.0,
        "typing_contribution_to_interaction_intensity": meta["typing_contribution_to_interaction_intensity"] as? Double ?? 0.0,
        "deep_typing_blocks": meta["deep_typing_blocks"] as? Int ?? 0,
        "typing_fragmentation": meta["typing_fragmentation"] as? Double ?? 0.0,
        "correction_rate": meta["correction_rate"] as? Double ?? 0.0,
        "clipboard_activity_rate": meta["clipboard_activity_rate"] as? Double ?? 0.0,
        "typing_metrics": extractTypingMetrics(meta["typing_metrics"] as? [[String: Any]])
    ]
}

/// Extract individual typing session metrics from Flux's typing_metrics array.
private func extractTypingMetrics(_ metricsArray: [[String: Any]]?) -> [[String: Any]] {
    guard let metricsArray = metricsArray else { return [] }
    return metricsArray.map { metric in
        // Extract values first to help Swift compiler type-check
        let startAt = metric["start_at"] as? String ?? ""
        let endAt = metric["end_at"] as? String ?? ""
        let duration = metric["duration"] as? Int ?? 0
        let deepTyping = metric["deep_typing"] as? Bool ?? false
        let typingTapCount = metric["typing_tap_count"] as? Int ?? 0
        let typingSpeed = metric["typing_speed"] as? Double ?? 0.0
        let meanInterTapInterval = metric["mean_inter_tap_interval_ms"] as? Double ?? 0.0
        let typingCadenceVariability = metric["typing_cadence_variability"] as? Double ?? 0.0
        let typingCadenceStability = metric["typing_cadence_stability"] as? Double ?? 0.0
        let typingGapCount = metric["typing_gap_count"] as? Int ?? 0
        let typingGapRatio = metric["typing_gap_ratio"] as? Double ?? 0.0
        let typingBurstiness = metric["typing_burstiness"] as? Double ?? 0.0
        let typingActivityRatio = metric["typing_activity_ratio"] as? Double ?? 0.0
        let typingInteractionIntensity = metric["typing_interaction_intensity"] as? Double ?? 0.0
        
        let numberOfBackspace = metric["number_of_backspace"] as? Int ?? 0
        let numberOfDelete = metric["number_of_delete"] as? Int ?? 0
        let numberOfCut = metric["number_of_cut"] as? Int ?? 0
        let numberOfPaste = metric["number_of_paste"] as? Int ?? 0
        let numberOfCopy = metric["number_of_copy"] as? Int ?? 0

        // Build dictionary with extracted values
        return [
            "start_at": startAt,
            "end_at": endAt,
            "duration": duration,
            "deep_typing": deepTyping,
            "typing_tap_count": typingTapCount,
            "typing_speed": typingSpeed,
            "mean_inter_tap_interval_ms": meanInterTapInterval,
            "typing_cadence_variability": typingCadenceVariability,
            "typing_cadence_stability": typingCadenceStability,
            "typing_gap_count": typingGapCount,
            "typing_gap_ratio": typingGapRatio,
            "typing_burstiness": typingBurstiness,
            "typing_activity_ratio": typingActivityRatio,
            "typing_interaction_intensity": typingInteractionIntensity,
            "number_of_backspace": numberOfBackspace,
            "number_of_delete": numberOfDelete,
            "number_of_cut": numberOfCut,
            "number_of_paste": numberOfPaste,
            "number_of_copy": numberOfCopy
        ]
    }
}
