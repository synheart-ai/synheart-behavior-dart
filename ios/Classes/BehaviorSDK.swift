import Foundation
import UIKit
import SystemConfiguration
import UserNotifications
import CoreTelephony

/// Main BehaviorSDK class for collecting behavioral signals on iOS.
/// Privacy-first: No text content, no PII - only timing and interaction patterns.
public class BehaviorSDK {

    private let config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var currentSessionId: String?
    private var sessionData: [String: SessionData] = [:]
    private let statsCollector = StatsCollector()

    // Signal collectors
    private let inputSignalCollector: InputSignalCollector
    private let attentionSignalCollector: AttentionSignalCollector
    private let gestureCollector: GestureCollector
    private let notificationCollector: NotificationCollector
    private let callCollector: CallCollector

    // Lifecycle tracking
    private var lastInteractionTime = Date()
    private var lastAppUseTime: Date? // For session spacing calculation
    private var idleTimer: Timer?
    
    // Device context tracking
    private var startScreenBrightness: CGFloat = 0.5
    private var startOrientation: UIDeviceOrientation = .portrait
    private var lastOrientation: UIDeviceOrientation = .portrait // Track last orientation to detect all changes
    private var orientationChangeCount: Int = 0
    
    // System state tracking
    private var startInternetState: Bool = false
    private var startDoNotDisturb: Bool = false
    private var startCharging: Bool = false

    public init(config: BehaviorConfig) {
        self.config = config
        self.inputSignalCollector = InputSignalCollector(config: config)
        self.attentionSignalCollector = AttentionSignalCollector(config: config)
        self.gestureCollector = GestureCollector(config: config)
        self.notificationCollector = NotificationCollector(config: config)
        self.callCollector = CallCollector(config: config)
    }

    public func initialize() {
        // Set up event handlers
        inputSignalCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        attentionSignalCollector.setEventHandler { [weak self] event in
            // App switches are tracked in session data, not emitted as events
            // Update app switch count when app foregrounds
            if let sessionId = self?.currentSessionId, var data = self?.sessionData[sessionId] {
                // App switch count is tracked by AttentionSignalCollector
                // We'll update it when needed
            }
        }

        gestureCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        notificationCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        callCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        attentionSignalCollector.startMonitoring()
        notificationCollector.startMonitoring()
        callCollector.startMonitoring()
        
        // Track app lifecycle for app switch counting
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Start idle detection
        startIdleTimer()
    }
    
    @objc private func appDidBecomeActive() {
        // Sync app switch count from AttentionSignalCollector
        // The AttentionSignalCollector tracks app switches correctly (only when transitioning from background)
        if let sessionId = currentSessionId, var data = sessionData[sessionId] {
            let currentAppSwitchCount = attentionSignalCollector.getAppSwitchCount()
            // Only update if the count has increased (to avoid resetting on first launch)
            if currentAppSwitchCount > data.appSwitchCount {
                data.appSwitchCount = currentAppSwitchCount
                sessionData[sessionId] = data
            }
        }
        lastAppUseTime = Date()
    }

    public func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
    }

    public func startSession(sessionId: String) {
        print("BehaviorSDK.startSession: Called with sessionId: \(sessionId)")
        currentSessionId = sessionId
        let now = Date()
        let nowMs = now.timeIntervalSince1970 * 1000
        
        // Reset app switch count for new session
        attentionSignalCollector.resetAppSwitchCount()
        
        // Capture device context at session start
        startScreenBrightness = getScreenBrightness()
        startOrientation = UIDevice.current.orientation
        lastOrientation = startOrientation // Initialize last orientation to start orientation
        orientationChangeCount = 0
        
        // Capture system state at session start
        startInternetState = isInternetConnected()
        startDoNotDisturb = isDoNotDisturbEnabled()
        startCharging = isCharging()
        
        // Calculate session spacing (time between end of previous session and start of current session)
        let sessionSpacing: Double
        if let lastUse = lastAppUseTime {
            sessionSpacing = (now.timeIntervalSince1970 - lastUse.timeIntervalSince1970) * 1000
        } else {
            sessionSpacing = 0
        }
        
        sessionData[sessionId] = SessionData(
            sessionId: sessionId,
            startTime: nowMs,
            sessionSpacing: Int64(sessionSpacing),
            startScreenBrightness: Double(startScreenBrightness),
            startOrientation: startOrientation.rawValue,
            startInternetState: startInternetState,
            startDoNotDisturb: startDoNotDisturb,
            startCharging: startCharging
        )
        
        print("BehaviorSDK.startSession: Session created and stored. sessionData keys: \(sessionData.keys)")
        print("BehaviorSDK.startSession: Session data for \(sessionId): eventCount=\(sessionData[sessionId]?.eventCount ?? -1)")
        
        lastInteractionTime = now
        // Don't update lastAppUseTime here - it will be updated when session ends
        
        // Register for orientation change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func orientationDidChange() {
        let currentOrientation = UIDevice.current.orientation
        // Count orientation changes by comparing with last orientation, not just start orientation
        // This ensures we count all changes (portrait->landscape->portrait = 2 changes)
        if currentOrientation != lastOrientation && 
           currentOrientation.isValidInterfaceOrientation &&
           currentSessionId != nil {
            orientationChangeCount += 1
            lastOrientation = currentOrientation // Update last orientation
            if let sessionId = currentSessionId, var data = sessionData[sessionId] {
                data.orientationChangeCount = orientationChangeCount
                sessionData[sessionId] = data
            }
            print("BehaviorSDK: Orientation changed: count=\(orientationChangeCount), current=\(currentOrientation.rawValue)")
        }
    }
    
    private func getScreenBrightness() -> CGFloat {
        return UIScreen.main.brightness
    }
    
    private func isInternetConnected() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        return isReachable && !needsConnection
    }
    
    private func isDoNotDisturbEnabled() -> Bool {
        // On iOS, there is no public API to detect Do Not Disturb status
        // Apple restricts access to DND settings for privacy reasons
        // This would require private APIs which are not allowed in App Store apps
        // Therefore, we always return false (DND not detected)
        return false
    }
    
    private func isCharging() -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    public func endSession(sessionId: String) throws -> [String: Any] {
        print("BehaviorSDK.endSession: Called with sessionId: \(sessionId)")
        print("BehaviorSDK.endSession: sessionData keys: \(sessionData.keys)")
        print("BehaviorSDK.endSession: currentSessionId: \(String(describing: currentSessionId))")
        guard var data = sessionData[sessionId] else {
            print("BehaviorSDK.endSession: ERROR - Session not found in sessionData!")
            throw NSError(domain: "BehaviorSDK", code: 404, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        print("BehaviorSDK.endSession: Session data found, eventCount: \(data.eventCount), events.count: \(data.events.count)")

        // Sync app switch count from AttentionSignalCollector before ending session
        let currentAppSwitchCount = attentionSignalCollector.getAppSwitchCount()
        if currentAppSwitchCount > data.appSwitchCount {
            data.appSwitchCount = currentAppSwitchCount
        }

        data.endTime = Date().timeIntervalSince1970 * 1000
        
        // Update lastAppUseTime to session end time for next session's spacing calculation
        // Session spacing = time between end_session and start_session
        lastAppUseTime = Date(timeIntervalSince1970: data.endTime / 1000)
        
        let duration = data.endTime - data.startTime
        let durationSeconds = duration / 1000.0
        let microSession = durationSeconds < 30.0 // Micro session threshold: <30s
        
        // Get OS version
        let osVersion = "iOS \(UIDevice.current.systemVersion)"
        
        // Get app ID (bundle identifier)
        let appId = Bundle.main.bundleIdentifier ?? "unknown"
        
        // Get app name from bundle info
        let appName: String
        if let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String {
            appName = displayName
        } else if let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String {
            appName = bundleName
        } else {
            appName = appId // Fallback to bundle identifier if unable to get app name
        }
        
        // Calculate average screen brightness (start + end) / 2
        let endScreenBrightness = getScreenBrightness()
        let avgScreenBrightness = (data.startScreenBrightness + Double(endScreenBrightness)) / 2.0
        
        // Get orientation string
        let startOrientationStr: String
        switch data.startOrientation {
        case UIDeviceOrientation.landscapeLeft.rawValue, UIDeviceOrientation.landscapeRight.rawValue:
            startOrientationStr = "landscape"
        default:
            startOrientationStr = "portrait"
        }
        
        // Get system state at end
        let endInternetState = isInternetConnected()
        let endDoNotDisturb = isDoNotDisturbEnabled()
        let endCharging = isCharging()
        
        // Compute notification summary from events
        let notificationEvents = data.events.filter { $0.eventType == "notification" }
        let notificationCount = notificationEvents.count
        let notificationIgnored = notificationEvents.filter { 
            ($0.metrics["action"] as? String) == "ignored" 
        }.count
        let notificationOpened = notificationEvents.filter { 
            ($0.metrics["action"] as? String) == "opened" 
        }.count
        let notificationIgnoreRate = notificationCount > 0 ? 
            Double(notificationIgnored) / Double(notificationCount) : 0.0
        
        // Compute notification clustering index
        let notificationClusteringIndex = computeNotificationClusteringIndex(notificationEvents)
        
        // Compute call summary
        let callEvents = data.events.filter { $0.eventType == "call" }
        let callCount = callEvents.count
        let callIgnored = callEvents.filter { 
            ($0.metrics["action"] as? String) == "ignored" 
        }.count
        
        // Compute behavioral metrics from events
        let behavioralMetrics = computeBehavioralMetrics(data: data, durationMs: Int64(duration), notificationCount: notificationCount, callCount: callCount)
        
        // Compute typing session summary
        let typingSessionSummary = computeTypingSessionSummary(data: data, durationMs: Int64(duration))
        
        // Build comprehensive summary
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var summary: [String: Any] = [
            "session_id": sessionId,
            "start_at": formatter.string(from: Date(timeIntervalSince1970: data.startTime / 1000)),
            "end_at": formatter.string(from: Date(timeIntervalSince1970: data.endTime / 1000)),
            "micro_session": microSession,
            "OS": osVersion,
            "app_id": appId,
            "app_name": appName,
            "session_spacing": data.sessionSpacing,
            "device_context": [
                "avg_screen_brightness": avgScreenBrightness,
                "start_orientation": startOrientationStr,
                "orientation_changes": data.orientationChangeCount
            ],
            "activity_summary": [
                "total_events": data.eventCount,
                "app_switch_count": data.appSwitchCount
            ],
            "behavioral_metrics": behavioralMetrics,
            "notification_summary": [
                "notification_count": notificationCount,
                "notification_ignored": notificationIgnored,
                "notification_ignore_rate": notificationIgnoreRate,
                "notification_clustering_index": notificationClusteringIndex,
                "call_count": callCount,
                "call_ignored": callIgnored
            ],
            "system_state": [
                "internet_state": endInternetState,
                "do_not_disturb": endDoNotDisturb,
                "charging": endCharging
            ]
        ]
        
        // Add typing session summary if available
        if !typingSessionSummary.isEmpty {
            summary["typing_session_summary"] = typingSessionSummary
        }

        sessionData.removeValue(forKey: sessionId)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        return summary
    }
    
    private func computeNotificationClusteringIndex(_ notificationEvents: [BehaviorEvent]) -> Double {
        if notificationEvents.count < 2 { return 0.0 }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Compute time intervals between notifications
        var intervals: [Double] = []
        for i in 1..<notificationEvents.count {
            if let prevDate = formatter.date(from: notificationEvents[i-1].timestamp),
               let currDate = formatter.date(from: notificationEvents[i].timestamp) {
                let interval = (currDate.timeIntervalSince1970 - prevDate.timeIntervalSince1970) * 1000
                intervals.append(interval)
            }
        }
        
        if intervals.isEmpty { return 0.0 }
        
        // Compute coefficient of variation (lower CV = more clustered)
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        if mean == 0.0 { return 0.0 }
        
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / mean
        
        // Clustering index: 1 - normalized CV (higher = more clustered)
        return max(0.0, min(1.0, 1.0 - (cv / 10.0)))
    }
    
    private func computeBehavioralMetrics(data: SessionData, durationMs: Int64, notificationCount: Int, callCount: Int) -> [String: Any] {
        let durationSeconds = Double(durationMs) / 1000.0
        
        // Step 1: Compute inter-event times for burstiness (Barabási's burstiness index)
        let burstiness = computeBurstiness(events: data.events)
        
        // Step 2: Compute notification_load = 1 - exp(-notification_rate / λ)
        // where notification_rate = notification_count / session_duration_seconds
        // λ = 1/60 (sensitivity parameter)
        let notificationRate = durationSeconds > 0 ? Double(notificationCount) / durationSeconds : 0.0
        let lambda = 1.0 / 60.0
        let notificationLoad = notificationRate > 0 ? 1.0 - exp(-notificationRate / lambda) : 0.0
        
        // Step 3: Compute task_switch_rate = 1 - exp(-task_switch_rate_raw / μ)
        // where task_switch_rate_raw = app_switch_count / session_duration
        // μ = 1/30 (task-switch tolerance)
        let taskSwitchRateRaw = durationSeconds > 0 ? Double(data.appSwitchCount) / durationSeconds : 0.0
        let mu = 1.0 / 30.0
        let taskSwitchRate = taskSwitchRateRaw > 0 ? 1.0 - exp(-taskSwitchRateRaw / mu) : 0.0
        
        // Step 4: Compute task_switch_cost = session duration during app_switch
        // Since we don't track individual app switch durations, estimate as average time per switch
        let taskSwitchCost = data.appSwitchCount > 0 ? 
            max(0, min(10000, Int(durationMs) / data.appSwitchCount)) : 0
        
        // Step 5: Compute idle_ratio = total_idle_time / session_duration
        // where total_idle_time = Σ Δtᵢ where Δtᵢ > idle_threshold (30 seconds)
        let idleRatio = computeIdleRatio(events: data.events, durationMs: durationMs)
        
        // Step 6: Compute active_interaction_time = session_duration - idle_time - task_switch_cost
        let totalIdleTimeMs = Int64(idleRatio * Double(durationMs))
        let activeInteractionTimeMs = durationMs - totalIdleTimeMs - Int64(taskSwitchCost)
        let activeTimeRatio = durationMs > 0 ? 
            max(0.0, min(1.0, Double(activeInteractionTimeMs) / Double(durationMs))) : 0.0
        
        // Step 7: Compute fragmented_idle_ratio = number_of_idle_segments / session_duration
        let fragmentedIdleRatio = computeFragmentedIdleRatio(events: data.events, durationMs: durationMs)
        
        // Step 8: Compute scroll_jitter_rate = direction_reversals / max(total_scroll_events - 1, 1)
        let scrollJitterRate = computeScrollJitterRate(events: data.events)
        
        // Step 9: Compute distraction_score = weighted combination
        // w1=0.35, w2=0.30, w3=0.20, w4=0.15
        let w1 = 0.35
        let w2 = 0.30
        let w3 = 0.20
        let w4 = 0.15
        let behavioralDistractionScore = max(0.0, min(1.0, 
            w1 * taskSwitchRate +
            w2 * notificationLoad +
            w3 * fragmentedIdleRatio +
            w4 * scrollJitterRate))
        
        // Step 10: Compute focus_hint = 1 - distraction_score
        let focusHint = 1.0 - behavioralDistractionScore
        
        // Step 11: Compute interaction_intensity = [total events except interruptions and typing +
        // (Typing durations/10s)] / session_duration
        // Interruptions = notifications, calls, app switches
        // Typing events are handled separately: we add (total_typing_duration_seconds / 10) instead
        // of counting typing events
        let interruptionCount = notificationCount + callCount + data.appSwitchCount
        
        // Count typing events to exclude them from event count
        let typingEvents = data.events.filter { $0.eventType == "typing" }
        let typingEventCount = typingEvents.count
        
        // Calculate total typing duration in seconds (sum of all typing session durations)
        let totalTypingDurationSeconds = typingEvents.isEmpty ? 0.0 :
            Double(typingEvents.compactMap { event -> Int? in
                if let duration = event.metrics["duration"] as? NSNumber {
                    return duration.intValue
                }
                return nil
            }.reduce(0, +))
        
        // Total events excluding interruptions and typing events
        let totalEventsExceptInterruptionsAndTyping = data.eventCount - interruptionCount - typingEventCount
        
        // Interaction intensity = [non-interruption non-typing events + (typing_duration/10)] / session_duration
        let typingContribution = totalTypingDurationSeconds / 10.0
        let interactionIntensity = durationSeconds > 0 ? 
            max(0.0, (Double(totalEventsExceptInterruptionsAndTyping) + typingContribution) / durationSeconds) : 0.0
        
        // Step 12: Compute deep_focus_block = continuous app engagement ≥ 120s without
        // idle, app switch, notification or call event
        let deepFocusBlocks = computeDeepFocusBlocks(events: data.events, durationMs: durationMs, sessionStartTime: data.startTime, sessionEndTime: data.endTime, notificationCount: notificationCount, callCount: callCount, appSwitchCount: data.appSwitchCount)
        
        return [
            "interaction_intensity": interactionIntensity,
            "task_switch_rate": taskSwitchRate,
            "task_switch_cost": taskSwitchCost,
            "idle_time_ratio": idleRatio,
            "active_time_ratio": activeTimeRatio,
            "notification_load": notificationLoad,
            "burstiness": burstiness,
            "behavioral_distraction_score": behavioralDistractionScore,
            "focus_hint": focusHint,
            "fragmented_idle_ratio": fragmentedIdleRatio,
            "scroll_jitter_rate": scrollJitterRate,
            "deep_focus_blocks": deepFocusBlocks
        ]
    }
    
    private func computeIdleRatio(events: [BehaviorEvent], durationMs: Int64) -> Double {
        if events.count < 2 { return 0.0 }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let idleThresholdMs: Double = 30000 // 30 seconds
        var totalIdleTime: Double = 0
        for i in 1..<events.count {
            if let prevDate = formatter.date(from: events[i-1].timestamp),
               let currDate = formatter.date(from: events[i].timestamp) {
                let gap = (currDate.timeIntervalSince1970 - prevDate.timeIntervalSince1970) * 1000
                if gap > idleThresholdMs {
                    totalIdleTime += gap - idleThresholdMs
                }
            }
        }
        
        return durationMs > 0 ? max(0.0, min(1.0, totalIdleTime / Double(durationMs))) : 0.0
    }
    
    private func computeFragmentedIdleRatio(events: [BehaviorEvent], durationMs: Int64) -> Double {
        if events.count < 2 { return 0.0 }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let idleThresholdMs: Double = 30000 // 30 seconds
        var numberOfIdleSegments = 0
        for i in 1..<events.count {
            if let prevDate = formatter.date(from: events[i-1].timestamp),
               let currDate = formatter.date(from: events[i].timestamp) {
                let gap = (currDate.timeIntervalSince1970 - prevDate.timeIntervalSince1970) * 1000
                if gap > idleThresholdMs {
                    numberOfIdleSegments += 1
                }
            }
        }
        
        let durationSeconds = Double(durationMs) / 1000.0
        return durationSeconds > 0 ? max(0.0, Double(numberOfIdleSegments) / durationSeconds) : 0.0
    }
    
    private func computeScrollJitterRate(events: [BehaviorEvent]) -> Double {
        let scrollEvents = events.filter { $0.eventType == "scroll" }
        if scrollEvents.count < 2 { return 0.0 }
        
        var directionReversals = 0
        var previousDirection: String? = nil
        for event in scrollEvents {
            let currentDirection = event.metrics["direction"] as? String
            if let current = currentDirection, let previous = previousDirection, current != previous {
                directionReversals += 1
            }
            previousDirection = currentDirection
        }
        
        let totalScrollEvents = scrollEvents.count
        return totalScrollEvents > 1 ? 
            max(0.0, min(1.0, Double(directionReversals) / Double(totalScrollEvents - 1))) : 0.0
    }
    
    private func computeBurstiness(events: [BehaviorEvent]) -> Double {
        if events.count < 2 {
            return 0.0
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Step 1: Calculate all inter-event gaps with typing flag
        struct GapInfo {
            let gap: Double
            let involvesTyping: Bool
        }
        
        var gaps: [GapInfo] = []
        for i in 1..<events.count {
            if let prevDate = formatter.date(from: events[i-1].timestamp),
               let currDate = formatter.date(from: events[i].timestamp) {
                let gap = (currDate.timeIntervalSince1970 - prevDate.timeIntervalSince1970) * 1000
                
                // Check if this gap involves typing (either previous or current event is typing)
                let prevIsTyping = events[i - 1].eventType == "typing"
                let currIsTyping = events[i].eventType == "typing"
                let involvesTyping = prevIsTyping || currIsTyping
                
                gaps.append(GapInfo(gap: gap, involvesTyping: involvesTyping))
            }
        }
        
        if gaps.isEmpty {
            return 0.0
        }
        
        // Step 2: Find max gap excluding gaps that involve typing
        let maxNonTypingGap = gaps
            .filter { !$0.involvesTyping }
            .map { $0.gap }
            .max() ?? 0.0
        
        // Step 3: Cap typing gaps at max non-typing gap
        // If maxNonTypingGap is 0 (no non-typing events), use the gaps as-is
        let cappedGaps: [Double] = if maxNonTypingGap > 0 {
            gaps.map { gapInfo in
                if gapInfo.involvesTyping {
                    // Cap typing gaps at max non-typing gap
                    return min(gapInfo.gap, maxNonTypingGap)
                } else {
                    return gapInfo.gap
                }
            }
        } else {
            // If all events are typing or no non-typing gaps found, use gaps as-is
            gaps.map { $0.gap }
        }
        
        // Step 4: Calculate mean and standard deviation using capped gaps
        let mean = cappedGaps.reduce(0, +) / Double(cappedGaps.count)
        
        if mean == 0.0 {
            return 0.0
        }
        
        let variance = cappedGaps.map { pow($0 - mean, 2) }.reduce(0, +) / Double(cappedGaps.count)
        let stdDev = sqrt(variance)
        
        if stdDev == 0.0 {
            return 0.0
        }
        
        // Step 5: Apply Barabási's burstiness formula: (σ - μ)/(σ + μ) remapped to [0,1]
        let burstinessRaw = (stdDev - mean) / (stdDev + mean)
        let burstiness = max(0.0, min(1.0, (burstinessRaw + 1.0) / 2.0))
        
        return burstiness
    }
    
    private func computeTypingSessionSummary(data: SessionData, durationMs: Int64) -> [String: Any] {
        // Extract all typing events
        let typingEvents = data.events.filter { $0.eventType == "typing" }
        
        if typingEvents.isEmpty {
            return [
                "typing_session_count": 0,
                "average_keystrokes_per_session": 0.0,
                "average_typing_session_duration": 0.0,
                "average_typing_speed": 0.0,
                "average_typing_gap": 0.0,
                "average_inter_tap_interval": 0.0,
                "typing_cadence_stability": 0.0,
                "burstiness_of_typing": 0.0,
                "total_typing_duration": 0,
                "active_typing_ratio": 0.0,
                "typing_contribution_to_interaction_intensity": 0.0,
                "deep_typing_blocks": 0,
                "typing_fragmentation": 0.0,
                "typing_metrics": [] as [[String: Any]]
            ]
        }
        
        // Each typing event represents one typing session (from Flutter BehaviorTextField)
        let typingSessionCount = typingEvents.count
        
        // Extract metrics from each typing event
        let sessionMetrics = typingEvents.map { event -> [String: Any] in
            return [
                "typing_tap_count": (event.metrics["typing_tap_count"] as? NSNumber)?.intValue ?? 0,
                "typing_speed": (event.metrics["typing_speed"] as? NSNumber)?.doubleValue ?? 0.0,
                "duration": (event.metrics["duration"] as? NSNumber)?.intValue ?? 0,
                "mean_inter_tap_interval_ms": (event.metrics["mean_inter_tap_interval_ms"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_cadence_stability": (event.metrics["typing_cadence_stability"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_gap_ratio": (event.metrics["typing_gap_ratio"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_burstiness": (event.metrics["typing_burstiness"] as? NSNumber)?.doubleValue ?? 0.0,
                "deep_typing": (event.metrics["deep_typing"] as? Bool) ?? false,
                "start_at": (event.metrics["start_at"] as? String) ?? "",
                "end_at": (event.metrics["end_at"] as? String) ?? ""
            ]
        }
        
        // Aggregate metrics
        let averageKeystrokesPerSession = Double(sessionMetrics.map { ($0["typing_tap_count"] as? Int) ?? 0 }.reduce(0, +)) / Double(sessionMetrics.count)
        let averageTypingSessionDuration = Double(sessionMetrics.map { ($0["duration"] as? Int) ?? 0 }.reduce(0, +)) / Double(sessionMetrics.count)
        let averageTypingSpeed = sessionMetrics.map { ($0["typing_speed"] as? Double) ?? 0.0 }.reduce(0.0, +) / Double(sessionMetrics.count)
        
        // Calculate average typing gap from mean_inter_tap_interval_ms
        let averageTypingGap = sessionMetrics.map { ($0["mean_inter_tap_interval_ms"] as? Double) ?? 0.0 }.reduce(0.0, +) / Double(sessionMetrics.count)
        
        // Calculate average inter-tap interval across all sessions
        let averageInterTapInterval = sessionMetrics.isEmpty ? 0.0 : 
            sessionMetrics.map { ($0["mean_inter_tap_interval_ms"] as? Double) ?? 0.0 }.reduce(0.0, +) / Double(sessionMetrics.count)
        
        // Average cadence stability across sessions
        let typingCadenceStability = sessionMetrics.map { ($0["typing_cadence_stability"] as? Double) ?? 0.0 }.reduce(0.0, +) / Double(sessionMetrics.count)
        
        // Average burstiness across sessions
        let burstinessOfTyping = sessionMetrics.map { ($0["typing_burstiness"] as? Double) ?? 0.0 }.reduce(0.0, +) / Double(sessionMetrics.count)
        
        // Total typing duration (sum of all session durations)
        let totalTypingDuration = sessionMetrics.map { ($0["duration"] as? Int) ?? 0 }.reduce(0, +)
        
        // Active typing ratio = total typing duration / session duration
        let activeTypingRatio = durationMs > 0 ? 
            max(0.0, min(1.0, Double(totalTypingDuration * 1000) / Double(durationMs))) : 0.0
        
        // Typing contribution to interaction intensity = typing events / total events
        let typingContributionToInteractionIntensity = data.eventCount > 0 ? 
            Double(typingEvents.count) / Double(data.eventCount) : 0.0
        
        // Deep typing blocks = sessions with deep_typing == true
        let deepTypingBlocks = sessionMetrics.filter { ($0["deep_typing"] as? Bool) ?? false }.count
        
        // Typing fragmentation = average gap ratio across sessions
        let typingFragmentation = sessionMetrics.map { ($0["typing_gap_ratio"] as? Double) ?? 0.0 }.reduce(0.0, +) / Double(sessionMetrics.count)
        
        // Individual typing session metrics (for detailed breakdown)
        let individualMetrics = typingEvents.map { event -> [String: Any] in
            return [
                "start_at": (event.metrics["start_at"] as? String) ?? "",
                "end_at": (event.metrics["end_at"] as? String) ?? "",
                "duration": (event.metrics["duration"] as? NSNumber)?.intValue ?? 0,
                "deep_typing": (event.metrics["deep_typing"] as? Bool) ?? false,
                "typing_tap_count": (event.metrics["typing_tap_count"] as? NSNumber)?.intValue ?? 0,
                "typing_speed": (event.metrics["typing_speed"] as? NSNumber)?.doubleValue ?? 0.0,
                "mean_inter_tap_interval_ms": (event.metrics["mean_inter_tap_interval_ms"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_cadence_variability": (event.metrics["typing_cadence_variability"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_cadence_stability": (event.metrics["typing_cadence_stability"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_gap_count": (event.metrics["typing_gap_count"] as? NSNumber)?.intValue ?? 0,
                "typing_gap_ratio": (event.metrics["typing_gap_ratio"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_burstiness": (event.metrics["typing_burstiness"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_activity_ratio": (event.metrics["typing_activity_ratio"] as? NSNumber)?.doubleValue ?? 0.0,
                "typing_interaction_intensity": (event.metrics["typing_interaction_intensity"] as? NSNumber)?.doubleValue ?? 0.0
            ]
        }
        
        return [
            "typing_session_count": typingSessionCount,
            "average_keystrokes_per_session": averageKeystrokesPerSession,
            "average_typing_session_duration": averageTypingSessionDuration,
            "average_typing_speed": averageTypingSpeed,
            "average_typing_gap": averageTypingGap,
            "average_inter_tap_interval": averageInterTapInterval,
            "typing_cadence_stability": typingCadenceStability,
            "burstiness_of_typing": burstinessOfTyping,
            "total_typing_duration": totalTypingDuration,
            "active_typing_ratio": activeTypingRatio,
            "typing_contribution_to_interaction_intensity": typingContributionToInteractionIntensity,
            "deep_typing_blocks": deepTypingBlocks,
            "typing_fragmentation": typingFragmentation,
            "typing_metrics": individualMetrics
        ]
    }
    
    private func computeDeepFocusBlocks(events: [BehaviorEvent], durationMs: Int64, sessionStartTime: Double, sessionEndTime: Double, notificationCount: Int, callCount: Int, appSwitchCount: Int) -> [[String: Any]] {
        // Deep focus block = continuous app engagement ≥ 120s without
        // idle, app switch, notification or call event
        var deepFocusBlocks: [[String: Any]] = []
        let minBlockDurationMs: Double = 120000 // 120 seconds
        
        if events.count < 2 { return deepFocusBlocks }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let idleThresholdMs: Double = 30000 // 30 seconds
        var blockStart: Date? = nil
        var blockEnd: Date? = nil
        var lastBlockEndTime: Date? = nil // Track when last block ended
        let sessionStartDate = Date(timeIntervalSince1970: sessionStartTime / 1000)
        
        // Filter out interruption events (notifications, calls, app switches)
        let interruptionEventTypes = Set(["notification", "call", "app_switch"])
        
        for i in 0..<events.count {
            guard let currDate = formatter.date(from: events[i].timestamp) else {
                continue
            }
            
            let event = events[i]
            let isInterruption = interruptionEventTypes.contains(event.eventType)
            
            // Check gap from previous event
            let gap: Double
            if i > 0, let prevDate = formatter.date(from: events[i - 1].timestamp) {
                gap = (currDate.timeIntervalSince1970 - prevDate.timeIntervalSince1970) * 1000
            } else {
                // First event - check gap from session start
                gap = (currDate.timeIntervalSince1970 - sessionStartDate.timeIntervalSince1970) * 1000
            }
            
            // If we hit an interruption or idle gap, end current block
            if isInterruption || gap > idleThresholdMs {
                if let start = blockStart, let end = blockEnd {
                    let blockDuration = (end.timeIntervalSince1970 - start.timeIntervalSince1970) * 1000
                    if blockDuration >= minBlockDurationMs {
                        deepFocusBlocks.append([
                            "start_at": formatter.string(from: start),
                            "end_at": formatter.string(from: end),
                            "duration_ms": Int(blockDuration)
                        ])
                    }
                }
                lastBlockEndTime = isInterruption ? currDate : blockEnd
                blockStart = nil
                blockEnd = nil
            } else {
                // Continue or start a focus block
                if blockStart == nil {
                    // Starting a new block - check if we should start from session start or previous block end
                    if i == 0 && gap <= idleThresholdMs {
                        // First event and close to session start - start from session start
                        blockStart = sessionStartDate
                    } else if let lastEnd = lastBlockEndTime, (currDate.timeIntervalSince1970 - lastEnd.timeIntervalSince1970) * 1000 <= idleThresholdMs {
                        // Close to previous block end - start from previous block end
                        blockStart = lastEnd
                    } else {
                        // Start from current event time
                        blockStart = currDate
                    }
                }
                blockEnd = currDate
            }
        }
        
        // Check final block - include time from last event to session end if recent
        if let start = blockStart, let end = blockEnd {
            // Get the last event time in the block (in milliseconds since 1970)
            let lastEventTime = end.timeIntervalSince1970 * 1000
            
            // If last event was recent (within idle threshold of session end), extend to session end
            // This ensures we count engagement time even if no events were generated at the end
            let timeFromLastEventToSessionEnd = sessionEndTime - lastEventTime
            let finalBlockEnd: Date
            if timeFromLastEventToSessionEnd <= idleThresholdMs {
                // Last event was recent, include time up to session end
                finalBlockEnd = Date(timeIntervalSince1970: sessionEndTime / 1000)
            } else {
                // Last event was too long ago, use event timestamp
                finalBlockEnd = end
            }
            
            let blockDuration = (finalBlockEnd.timeIntervalSince1970 - start.timeIntervalSince1970) * 1000
            if blockDuration >= minBlockDurationMs {
                deepFocusBlocks.append([
                    "start_at": formatter.string(from: start),
                    "end_at": formatter.string(from: finalBlockEnd),
                    "duration_ms": Int(blockDuration)
                ])
            }
        }
        
        return deepFocusBlocks
    }

    public func getCurrentStats() -> BehaviorStats {
        return statsCollector.getCurrentStats()
    }

    public func updateConfig(_ newConfig: BehaviorConfig) {
        inputSignalCollector.updateConfig(newConfig)
        attentionSignalCollector.updateConfig(newConfig)
        gestureCollector.updateConfig(newConfig)
        notificationCollector.updateConfig(newConfig)
        callCollector.updateConfig(newConfig)
    }

    public func attachToView(_ view: UIView) {
        if config.enableInputSignals {
            inputSignalCollector.attachToView(view)
            gestureCollector.attachToView(view)
        }
    }

    public func dispose() {
        idleTimer?.invalidate()
        idleTimer = nil
        NotificationCenter.default.removeObserver(self)
        inputSignalCollector.dispose()
        attentionSignalCollector.dispose()
        gestureCollector.dispose()
        notificationCollector.dispose()
        callCollector.dispose()
    }

    public func onUserInteraction() {
        let now = Date()
        lastInteractionTime = now
        lastAppUseTime = now
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIdleState()
        }
    }

    private func checkIdleState() {
        // Idle is now computed from gaps between events in the feature extractor
        // No need to emit separate idle events
    }

    // Public method to receive events from Flutter
    public func receiveEventFromFlutter(_ event: BehaviorEvent) {
        emitEvent(event)
    }
    
    private func emitEvent(_ event: BehaviorEvent) {
        // Replace "current" session ID with actual session ID
        let eventWithSessionId: BehaviorEvent
        if event.sessionId == "current", let sessionId = currentSessionId {
            eventWithSessionId = BehaviorEvent(
                eventId: event.eventId,
                sessionId: sessionId,
                timestamp: event.timestamp,
                eventType: event.eventType,
                metrics: event.metrics
            )
        } else {
            eventWithSessionId = event
        }
        
        eventHandler?(eventWithSessionId)

        let sessionId = currentSessionId ?? eventWithSessionId.sessionId
        if var data = sessionData[sessionId] {
            data.eventCount += 1
            data.events.append(eventWithSessionId) // Store event for session metrics

            // Update session-specific metrics based on new event types
            switch eventWithSessionId.eventType {
            case "tap":
                // Count taps that are not long press as keystrokes
                let longPress = eventWithSessionId.metrics["long_press"] as? Bool ?? false
                if !longPress {
                    data.totalKeystrokes += 1
                }
            case "scroll":
                data.scrollEventCount += 1
                if let velocity = eventWithSessionId.metrics["velocity"] as? Double {
                    data.totalScrollVelocity += velocity
                }
            // App switches will be tracked separately
            default:
                break
            }

            sessionData[sessionId] = data
        }
    }

    private func calculateStabilityIndex(data: SessionData) -> Double {
        let durationMinutes = (data.endTime - data.startTime) / 60000.0
        if durationMinutes == 0.0 { return 1.0 }
        let normalized = 1.0 - (Double(data.appSwitchCount) / (durationMinutes * 10.0))
        return max(0.0, min(1.0, normalized))
    }

    private func calculateFragmentationIndex(data: SessionData) -> Double {
        let durationMinutes = (data.endTime - data.startTime) / 60000.0
        if durationMinutes == 0.0 { return 0.0 }
        return max(0.0, min(1.0, Double(data.eventCount) / (durationMinutes * 20.0)))
    }
}

// MARK: - Configuration

public struct BehaviorConfig {
    public let enableInputSignals: Bool
    public let enableAttentionSignals: Bool
    public let enableMotionLite: Bool
    public let sessionIdPrefix: String?
    public let eventBatchSize: Int
    public let maxIdleGapSeconds: Double

    public init(
        enableInputSignals: Bool = true,
        enableAttentionSignals: Bool = true,
        enableMotionLite: Bool = false,
        sessionIdPrefix: String? = nil,
        eventBatchSize: Int = 10,
        maxIdleGapSeconds: Double = 10.0
    ) {
        self.enableInputSignals = enableInputSignals
        self.enableAttentionSignals = enableAttentionSignals
        self.enableMotionLite = enableMotionLite
        self.sessionIdPrefix = sessionIdPrefix
        self.eventBatchSize = eventBatchSize
        self.maxIdleGapSeconds = maxIdleGapSeconds
    }
}

// MARK: - Data Models

public struct BehaviorEvent {
    public let eventId: String
    public let sessionId: String
    public let timestamp: String // ISO 8601 format
    public let eventType: String // scroll, tap, swipe, notification, call
    public let metrics: [String: Any]

    public init(eventId: String? = nil, sessionId: String, timestamp: String? = nil, eventType: String, metrics: [String: Any]) {
        self.eventId = eventId ?? "evt_\(Int64(Date().timeIntervalSince1970 * 1000))"
        self.sessionId = sessionId
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = timestamp ?? formatter.string(from: Date())
        self.eventType = eventType
        self.metrics = metrics
    }

    public func toDictionary() -> [String: Any] {
        return [
            "event": [
                "event_id": eventId,
                "session_id": sessionId,
                "timestamp": timestamp,
                "event_type": eventType,
                "metrics": metrics
            ]
        ]
    }
    
    // Legacy format for backward compatibility during migration
    public func toLegacyDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampMs = formatter.date(from: timestamp)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        return [
            "session_id": sessionId,
            "timestamp": Int64(timestampMs * 1000),
            "type": eventType,
            "payload": metrics
        ]
    }
}

struct SessionData {
    let sessionId: String
    let startTime: Double
    var endTime: Double = 0
    var eventCount: Int = 0
    var totalKeystrokes: Int = 0
    var scrollEventCount: Int = 0
    var totalScrollVelocity: Double = 0.0
    var appSwitchCount: Int = 0
    let sessionSpacing: Int64 // Time since last app use
    let startScreenBrightness: Double
    let startOrientation: Int
    var orientationChangeCount: Int = 0
    let startInternetState: Bool
    let startDoNotDisturb: Bool
    let startCharging: Bool
    var events: [BehaviorEvent] = [] // Store events for session metrics
}

public struct SessionSummary {
    public let sessionId: String
    public let startTimestamp: Int64
    public let endTimestamp: Int64
    public let duration: Int64
    public let eventCount: Int
    public let averageTypingCadence: Double?
    public let averageScrollVelocity: Double?
    public let appSwitchCount: Int
    public let stabilityIndex: Double
    public let fragmentationIndex: Double

    public func toDictionary() -> [String: Any?] {
        return [
            "session_id": sessionId,
            "start_timestamp": startTimestamp,
            "end_timestamp": endTimestamp,
            "duration": duration,
            "event_count": eventCount,
            "average_typing_cadence": averageTypingCadence,
            "average_scroll_velocity": averageScrollVelocity,
            "app_switch_count": appSwitchCount,
            "stability_index": stabilityIndex,
            "fragmentation_index": fragmentationIndex
        ]
    }
}

public struct BehaviorStats {
    public let typingCadence: Double?
    public let interKeyLatency: Double?
    public let burstLength: Int?
    public let scrollVelocity: Double?
    public let scrollAcceleration: Double?
    public let scrollJitter: Double?
    public let tapRate: Double?
    public let appSwitchesPerMinute: Int
    public let foregroundDuration: Double?
    public let idleGapSeconds: Double?
    public let stabilityIndex: Double?
    public let fragmentationIndex: Double?
    public let timestamp: Int64

    public func toDictionary() -> [String: Any?] {
        return [
            "typing_cadence": typingCadence,
            "inter_key_latency": interKeyLatency,
            "burst_length": burstLength,
            "scroll_velocity": scrollVelocity,
            "scroll_acceleration": scrollAcceleration,
            "scroll_jitter": scrollJitter,
            "tap_rate": tapRate,
            "app_switches_per_minute": appSwitchesPerMinute,
            "foreground_duration": foregroundDuration,
            "idle_gap_seconds": idleGapSeconds,
            "stability_index": stabilityIndex,
            "fragmentation_index": fragmentationIndex,
            "timestamp": timestamp
        ]
    }
}
