import Flutter
import UIKit
import UserNotifications
import os.log

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
            print("SynheartBehaviorPlugin: endSession called")
            os_log("SynheartBehaviorPlugin: endSession called", log: OSLog.default, type: .info)
            let args = call.arguments as? [String: Any] ?? [:]
            let sessionId = args["sessionId"] as? String ?? ""
            print("SynheartBehaviorPlugin: sessionId = \(sessionId)")
            os_log("SynheartBehaviorPlugin: sessionId = %@", log: OSLog.default, type: .info, sessionId)
            print("SynheartBehaviorPlugin: behaviorSDK = \(String(describing: behaviorSDK))")
            os_log("SynheartBehaviorPlugin: behaviorSDK exists = %@", log: OSLog.default, type: .info, behaviorSDK != nil ? "YES" : "NO")
            
            guard let behaviorSDK = self.behaviorSDK else {
                let errorMsg = "SDK not initialized"
                print("SynheartBehaviorPlugin: ERROR - \(errorMsg)")
                os_log("SynheartBehaviorPlugin: ERROR - %@", log: OSLog.default, type: .error, errorMsg)
                result(FlutterError(code: "SDK_NOT_INITIALIZED", message: errorMsg, details: nil))
                return
            }
            
            do {
                print("SynheartBehaviorPlugin: Calling endSession...")
                os_log("SynheartBehaviorPlugin: Calling endSession...", log: OSLog.default, type: .info)
                let summary = try endSession(sessionId: sessionId)
                print("SynheartBehaviorPlugin: endSession succeeded, summary keys: \(summary.keys)")
                os_log("SynheartBehaviorPlugin: endSession succeeded, summary has %d keys", log: OSLog.default, type: .info, summary.count)
                result(summary)
            } catch {
                let errorMsg = error.localizedDescription
                print("SynheartBehaviorPlugin: endSession error: \(error)")
                os_log("SynheartBehaviorPlugin: endSession error: %@", log: OSLog.default, type: .error, errorMsg)
                result(FlutterError(code: "END_SESSION_ERROR", message: errorMsg, details: nil))
            }
        case "updateConfig":
            let config = call.arguments as? [String: Any] ?? [:]
            updateConfig(config: config)
            result(nil)
        case "dispose":
            dispose()
            result(nil)
        case "checkNotificationPermission":
            checkNotificationPermission(result: result)
        case "requestNotificationPermission":
            requestNotificationPermission(result: result)
        case "checkCallPermission":
            checkCallPermission(result: result)
        case "requestCallPermission":
            requestCallPermission(result: result)
        case "sendEvent":
            let eventData = call.arguments as? [String: Any] ?? [:]
            sendEvent(eventData: eventData)
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
        print("SynheartBehaviorPlugin.startSession: sessionId = \(sessionId)")
        print("SynheartBehaviorPlugin.startSession: behaviorSDK = \(String(describing: behaviorSDK))")
        currentSessionId = sessionId
        behaviorSDK?.startSession(sessionId: sessionId)
        print("SynheartBehaviorPlugin.startSession: Session started")
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

    private func endSession(sessionId: String) throws -> [String: Any] {
        print("SynheartBehaviorPlugin.endSession: Starting with sessionId: \(sessionId)")
        os_log("SynheartBehaviorPlugin.endSession: Starting with sessionId: %@", log: OSLog.default, type: .info, sessionId)
        
        guard let behaviorSDK = self.behaviorSDK else {
            let errorMsg = "SDK not initialized"
            print("SynheartBehaviorPlugin.endSession: ERROR - behaviorSDK is nil!")
            os_log("SynheartBehaviorPlugin.endSession: ERROR - %@", log: OSLog.default, type: .error, errorMsg)
            throw NSError(domain: "SynheartBehaviorPlugin", code: 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        print("SynheartBehaviorPlugin.endSession: Calling behaviorSDK.endSession...")
        os_log("SynheartBehaviorPlugin.endSession: Calling behaviorSDK.endSession...", log: OSLog.default, type: .info)
        let summary = try behaviorSDK.endSession(sessionId: sessionId)
        print("SynheartBehaviorPlugin.endSession: Success! Summary has \(summary.count) keys")
        os_log("SynheartBehaviorPlugin.endSession: Success! Summary has %d keys", log: OSLog.default, type: .info, summary.count)
        return summary
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
    

    private func checkNotificationPermission(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let isAuthorized = settings.authorizationStatus == .authorized || 
                                   settings.authorizationStatus == .provisional
                result(isAuthorized)
            }
        }
    }

    private func requestNotificationPermission(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(granted)
                }
            }
        }
    }

    private func checkCallPermission(result: @escaping FlutterResult) {
        // iOS CoreTelephony doesn't require explicit permission
        // Call monitoring works without user permission
        result(true)
    }

    private func requestCallPermission(result: @escaping FlutterResult) {
        // iOS CoreTelephony doesn't require explicit permission
        // No action needed
        result(nil)
    }
    
    private func sendEvent(eventData: [String: Any]) {
        guard let behaviorSDK = self.behaviorSDK else { return }
        
        // Parse event data from Dart
        // Format: {"event": {"event_id": "...", "session_id": "...", "timestamp": "...",
        // "event_type": "...", "metrics": {...}}}
        let eventMap = eventData["event"] as? [String: Any] ?? eventData
        let eventId = eventMap["event_id"] as? String ?? "evt_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let sessionId = eventMap["session_id"] as? String ?? "current"
        let timestamp = eventMap["timestamp"] as? String
        let eventType = eventMap["event_type"] as? String ?? "tap"
        let metrics = eventMap["metrics"] as? [String: Any] ?? [:]
        
        let event = BehaviorEvent(
            eventId: eventId,
            sessionId: sessionId,
            timestamp: timestamp,
            eventType: eventType,
            metrics: metrics
        )
        
        behaviorSDK.receiveEventFromFlutter(event)
    }
}

