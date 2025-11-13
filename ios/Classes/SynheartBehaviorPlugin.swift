import Flutter
import UIKit

public class SynheartBehaviorPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var currentSessionId: String?
    private var isInitialized = false
    private var behaviorSDK: BehaviorSDK?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ai.synheart.behavior",
            binaryMessenger: registrar.messenger()
        )
        let instance = SynheartBehaviorPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            let config = call.arguments as? [String: Any] ?? [:]
            initialize(config: config)
            result(nil)
        case "startSession":
            let args = call.arguments as? [String: Any] ?? [:]
            let sessionId = args["sessionId"] as? String ?? generateSessionId()
            startSession(sessionId: sessionId)
            result(nil)
        case "getCurrentStats":
            let stats = getCurrentStats()
            result(stats)
        case "endSession":
            let args = call.arguments as? [String: Any] ?? [:]
            let sessionId = args["sessionId"] as? String ?? ""
            let summary = endSession(sessionId: sessionId)
            result(summary)
        case "updateConfig":
            let config = call.arguments as? [String: Any] ?? [:]
            updateConfig(config: config)
            result(nil)
        case "dispose":
            dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(config: [String: Any]) {
        let behaviorConfig = BehaviorConfig(
            enableInputSignals: config["enableInputSignals"] as? Bool ?? true,
            enableAttentionSignals: config["enableAttentionSignals"] as? Bool ?? true,
            enableMotionLite: config["enableMotionLite"] as? Bool ?? false,
            sessionIdPrefix: config["sessionIdPrefix"] as? String,
            eventBatchSize: config["eventBatchSize"] as? Int ?? 10,
            maxIdleGapSeconds: config["maxIdleGapSeconds"] as? Double ?? 10.0
        )

        behaviorSDK = BehaviorSDK(config: behaviorConfig)
        behaviorSDK?.initialize()
        behaviorSDK?.setEventHandler { [weak self] event in
            self?.emitEvent(event: event.toDictionary())
        }

        // Attach to root view if available
        if let window = UIApplication.shared.windows.first,
           let rootView = window.rootViewController?.view {
            behaviorSDK?.attachToView(rootView)
        }

        isInitialized = true
    }

    private func startSession(sessionId: String) {
        currentSessionId = sessionId
        behaviorSDK?.startSession(sessionId: sessionId)
    }

    private func getCurrentStats() -> [String: Any] {
        if let stats = behaviorSDK?.getCurrentStats() {
            return stats.toDictionary() as [String: Any]
        }
        return [
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "typing_cadence": nil as Any?,
            "inter_key_latency": nil as Any?,
            "burst_length": nil as Any?,
            "scroll_velocity": nil as Any?,
            "scroll_acceleration": nil as Any?,
            "scroll_jitter": nil as Any?,
            "tap_rate": nil as Any?,
            "app_switches_per_minute": 0,
            "foreground_duration": nil as Any?,
            "idle_gap_seconds": nil as Any?,
            "stability_index": nil as Any?,
            "fragmentation_index": nil as Any?,
        ]
    }

    private func endSession(sessionId: String) -> [String: Any] {
        do {
            if let summary = try behaviorSDK?.endSession(sessionId: sessionId) {
                return summary.toDictionary() as [String: Any]
            }
        } catch {
            // Return placeholder on error
        }

        let endTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return [
            "session_id": sessionId,
            "start_timestamp": endTimestamp,
            "end_timestamp": endTimestamp,
            "duration": 0,
            "event_count": 0,
            "average_typing_cadence": nil as Any?,
            "average_scroll_velocity": nil as Any?,
            "app_switch_count": 0,
            "stability_index": nil as Any?,
            "fragmentation_index": nil as Any?,
        ]
    }

    private func updateConfig(config: [String: Any]) {
        let behaviorConfig = BehaviorConfig(
            enableInputSignals: config["enableInputSignals"] as? Bool ?? true,
            enableAttentionSignals: config["enableAttentionSignals"] as? Bool ?? true,
            enableMotionLite: config["enableMotionLite"] as? Bool ?? false,
            sessionIdPrefix: config["sessionIdPrefix"] as? String,
            eventBatchSize: config["eventBatchSize"] as? Int ?? 10,
            maxIdleGapSeconds: config["maxIdleGapSeconds"] as? Double ?? 10.0
        )
        behaviorSDK?.updateConfig(behaviorConfig)
    }

    private func dispose() {
        behaviorSDK?.dispose()
        behaviorSDK = nil
        currentSessionId = nil
        isInitialized = false
    }

    private func generateSessionId() -> String {
        return "SESS-\(Int64(Date().timeIntervalSince1970 * 1000))"
    }

    // Helper method to emit events to Flutter
    private func emitEvent(event: [String: Any]) {
        channel?.invokeMethod("onEvent", arguments: event)
    }
}

