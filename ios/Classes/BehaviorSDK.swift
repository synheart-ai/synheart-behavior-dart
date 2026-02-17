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
    private var sessionMotionData: [String: [MotionSignalCollector.MotionDataPoint]] = [:]
    private let statsCollector = StatsCollector()

    // Signal collectors
    private let inputSignalCollector: InputSignalCollector
    private let attentionSignalCollector: AttentionSignalCollector
    private let gestureCollector: GestureCollector
    private let notificationCollector: NotificationCollector
    private let callCollector: CallCollector
    private let motionSignalCollector: MotionSignalCollector

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
        self.motionSignalCollector = MotionSignalCollector(config: config)
        
        // Initialize FluxBridge early to check availability
        _ = FluxBridge.shared
        print("BehaviorSDK: FluxBridge initialized, available: \(FluxBridge.shared.isAvailable)")
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
        // Clear previous session data when starting a new session
        // This ensures data persists until the next session starts, allowing
        // calculateMetricsForTimeRange to access it for ended sessions
        if let previousSessionId = currentSessionId, previousSessionId != sessionId {
            sessionData.removeValue(forKey: previousSessionId)
            sessionMotionData.removeValue(forKey: previousSessionId)
        }
        
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
        
        // Start motion data collection if enabled
        motionSignalCollector.startSession(sessionStartTime: nowMs)
        
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
        
        // Compute clipboard summary (tracked separately, not sent to Flux)
        let clipboardEvents = data.events.filter { $0.eventType == "clipboard" }
        let clipboardCount = clipboardEvents.count
        let clipboardCopyCount = clipboardEvents.filter {
            ($0.metrics["action"] as? String) == "copy"
        }.count
        let clipboardPasteCount = clipboardEvents.filter {
            ($0.metrics["action"] as? String) == "paste"
        }.count
        let clipboardCutCount = clipboardEvents.filter {
            ($0.metrics["action"] as? String) == "cut"
        }.count
        
        // correction_rate and clipboard_activity_rate come from Flux (no manual calculation)

        // Compute behavioral metrics from events
        // Use only Flux (Rust) calculations - native Swift calculations commented out
        let (calculationMetrics, fluxMetrics, performanceInfo) = computeBehavioralMetricsWithFlux(data: data, durationMs: Int64(duration), notificationCount: notificationCount, callCount: callCount)
        
        // Require Flux metrics - fail if not available
        guard let fluxMetrics = fluxMetrics else {
            throw NSError(domain: "BehaviorSDK", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is required but metrics are not available"])
        }
        
        // Compute typing session summary
        // Native Swift typing summary calculation commented out - using Flux typing summary instead
        // let typingSessionSummary = computeTypingSessionSummary(data: data, durationMs: Int64(duration))
        
        // Collect motion data if enabled
        let motionData = motionSignalCollector.stopSession()
        
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
            "behavioral_metrics": fluxMetrics, // Use Flux (Rust) results as primary
            // "behavioral_metrics_flux" removed - Flux is now the primary source
            "performance_info": performanceInfo,
            "notification_summary": [
                "notification_count": notificationCount,
                "notification_ignored": notificationIgnored,
                "notification_ignore_rate": notificationIgnoreRate,
                "notification_clustering_index": notificationClusteringIndex,
                "call_count": callCount,
                "call_ignored": callIgnored
            ],
            "clipboard_summary": [
                "clipboard_count": clipboardCount,
                "clipboard_copy_count": clipboardCopyCount,
                "clipboard_paste_count": clipboardPasteCount,
                "clipboard_cut_count": clipboardCutCount
            ],
            "system_state": [
                "internet_state": endInternetState,
                "do_not_disturb": endDoNotDisturb,
                "charging": endCharging
            ]
        ]
        
        // Add typing session summary from Flux (primary source)
        // Native typing summary commented out - using Flux typing summary instead
        // if !typingSessionSummary.isEmpty {
        //     summary["typing_session_summary"] = typingSessionSummary
        // }
        
        // Extract Flux typing session summary (correction_rate and clipboard_activity_rate from Flux)
        if let fluxTypingSummary = fluxMetrics["typing_session_summary"] as? [String: Any], !fluxTypingSummary.isEmpty {
            summary["typing_session_summary"] = fluxTypingSummary
        }
        
        // Add motion data if available
        if !motionData.isEmpty {
            let motionDataJson = motionData.map { dataPoint -> [String: Any] in
                return [
                    "timestamp": dataPoint.timestamp,
                    "features": dataPoint.features
                ]
            }
            summary["motion_data"] = motionDataJson
            
            // Store motion data for on-demand queries (will be cleared when next session starts)
            sessionMotionData[sessionId] = motionData
        }
        
        // Don't remove sessionData here - it will be cleared when the next session starts
        // This allows calculateMetricsForTimeRange to access data for ended sessions
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
    

    /// Compute behavioral metrics using Flux (Rust).
    ///
    /// Returns a tuple of (calculationMetrics, fluxMetrics, performanceInfo) where:
    /// - calculationMetrics: Empty dictionary (not used, kept for API compatibility)
    /// - fluxMetrics: Results from Rust (synheart-flux), or nil if Flux is unavailable/failed
    /// - performanceInfo: Contains execution time for Flux computation
    private func computeBehavioralMetricsWithFlux(data: SessionData, durationMs: Int64, notificationCount: Int, callCount: Int) -> ([String: Any], [String: Any]?, [String: Any]) {
        // Native Swift calculation commented out - using only Flux
        // let swiftStartTime = CFAbsoluteTimeGetCurrent()
        // let swiftMetrics = computeBehavioralMetrics(data: data, durationMs: durationMs, notificationCount: notificationCount, callCount: callCount)
        // let swiftTimeMs = Int64((CFAbsoluteTimeGetCurrent() - swiftStartTime) * 1000)
        // print("BehaviorSDK: Computed metrics using Swift (Calculation) - \(swiftTimeMs)ms")
        
        // Compute Flux (Rust) - required, fail if unavailable
        var fluxMetrics: [String: Any]? = nil
        var fluxTimeMs: Int64 = 0
        let fluxAvailable = FluxBridge.shared.isAvailable
        
        if fluxAvailable {
            do {
                let fluxStartTime = CFAbsoluteTimeGetCurrent()
                
            // Convert events to synheart-flux JSON format
            let eventTuples = data.events.map { event in
                (timestamp: event.timestamp, eventType: event.eventType, metrics: event.metrics)
            }

            let fluxJson = convertEventsToFluxJson(
                sessionId: data.sessionId,
                deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "ios-device",
                timezone: TimeZone.current.identifier,
                startTime: Date(timeIntervalSince1970: data.startTime / 1000),
                endTime: Date(timeIntervalSince1970: data.endTime / 1000),
                events: eventTuples
            )

                print("BehaviorSDK: Calling FluxBridge.behaviorToHsi with JSON length: \(fluxJson.count)")
                
                // DEBUG: Log the JSON being sent to Flux (first 1000 chars)
                let jsonPreview = fluxJson.count > 1000 ? 
                    String(fluxJson.prefix(1000)) + "..." : fluxJson
                print("BehaviorSDK: Flux JSON preview: \(jsonPreview)")
                
                // Call Rust to compute HSI metrics
                if let hsiJson = FluxBridge.shared.behaviorToHsi(fluxJson) {
                    print("BehaviorSDK: Got HSI JSON from Rust, length: \(hsiJson.count)")
                    
                    // DEBUG: Log HSI JSON preview to see scroll jitter calculation
                    let hsiPreview = hsiJson.count > 2000 ? 
                        String(hsiJson.prefix(2000)) + "..." : hsiJson
                    print("BehaviorSDK: HSI JSON preview: \(hsiPreview)")
                    
                    if let metrics = extractBehavioralMetricsFromHsi(hsiJson) {
                        fluxTimeMs = Int64((CFAbsoluteTimeGetCurrent() - fluxStartTime) * 1000)
                        fluxMetrics = metrics
                        print("BehaviorSDK: Successfully computed metrics using synheart-flux (Flux) - \(fluxTimeMs)ms")
                } else {
                        fluxTimeMs = Int64((CFAbsoluteTimeGetCurrent() - fluxStartTime) * 1000)
                        print("BehaviorSDK: Failed to extract metrics from HSI JSON")
            }
        } else {
                    fluxTimeMs = Int64((CFAbsoluteTimeGetCurrent() - fluxStartTime) * 1000)
                    print("BehaviorSDK: Rust computation returned nil (took \(fluxTimeMs)ms)")
                }
            } catch {
                print("BehaviorSDK: Flux computation failed: \(error.localizedDescription)")
                // Don't throw - just log the error and continue with Calculation results
            }
            } else {
            print("BehaviorSDK: Flux is not available - skipping Flux computation")
        }
        
        // Build performance info with Flux execution time only
        var performanceInfo: [String: Any] = [:]
        if let fluxMetrics = fluxMetrics {
            performanceInfo["flux_execution_time_ms"] = fluxTimeMs
            print("BehaviorSDK: Computed metrics using Flux (Rust) - \(fluxTimeMs)ms")
        }
        
        // Return empty dictionary for calculationMetrics (not used anymore)
        return ([String: Any](), fluxMetrics, performanceInfo)
    }


    public func getCurrentStats() -> BehaviorStats {
        return statsCollector.getCurrentStats()
    }

    public func calculateMetricsForTimeRange(
        startTimestampMs: Int64,
        endTimestampMs: Int64,
        sessionId: String?
    ) throws -> [String: Any] {
        // Determine which session to use
        let sessionIdToUse = sessionId ?? currentSessionId
        guard let sessionIdToUse = sessionIdToUse else {
            throw NSError(domain: "BehaviorSDK", code: 500, userInfo: [NSLocalizedDescriptionKey: "No active session and no sessionId provided"])
        }
        
        // Get session data (may be nil if session has ended)
        let sessionDataEntry = sessionData[sessionIdToUse]
        
        // Validate time range is within session duration (with 1 second tolerance)
        if let data = sessionDataEntry {
            let sessionStartMs = Int64(data.startTime)
            let sessionEndMs = Int64(data.endTime ?? Date().timeIntervalSince1970 * 1000)
            let toleranceMs: Int64 = 1000 // 1 second tolerance
            
            if startTimestampMs < (sessionStartMs - toleranceMs) || 
               endTimestampMs > (sessionEndMs + toleranceMs) {
                throw NSError(
                    domain: "BehaviorSDK",
                    code: 400,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Time range [\(startTimestampMs), \(endTimestampMs)] is out of session bounds [\(sessionStartMs), \(sessionEndMs)]. Session duration: \(sessionEndMs - sessionStartMs)ms. Allowed tolerance: \(toleranceMs)ms"
                    ]
                )
            }
        }
        
        // Filter events by time range
        let filteredEvents: [BehaviorEvent]
        if let data = sessionDataEntry {
            // Session is still active - get events from session data
            filteredEvents = data.events.filter { event in
                do {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    guard let eventDate = formatter.date(from: event.timestamp) else { return false }
                    let eventTimeMs = Int64(eventDate.timeIntervalSince1970 * 1000)
                    return eventTimeMs >= startTimestampMs && eventTimeMs <= endTimestampMs
                } catch {
                    return false // Skip invalid timestamps
                }
            }
        } else {
            // Session has ended - events should be retrieved from EventDatabase
            // For now, return empty list (EventDatabase integration can be added later)
            filteredEvents = []
        }
        
        // Calculate duration
        let duration = Int64(endTimestampMs - startTimestampMs)
        let durationSeconds = Double(duration) / 1000.0
        
        // Create a temporary SessionData for calculations
        var tempData = SessionData(
            sessionId: sessionIdToUse,
            startTime: Double(startTimestampMs),
            endTime: Double(endTimestampMs),
            eventCount: filteredEvents.count,
            appSwitchCount: filteredEvents.filter { $0.eventType == "app_switch" }.count,
            sessionSpacing: 0,
            startScreenBrightness: 0.5,
            startOrientation: UIDevice.current.orientation.rawValue,
            startInternetState: false,
            startDoNotDisturb: false,
            startCharging: false,
            events: filteredEvents
        )
        
        // Compute notification summary
        let notificationEvents = filteredEvents.filter { $0.eventType == "notification" }
        let notificationCount = notificationEvents.count
        let notificationIgnored = notificationEvents.filter {
            ($0.metrics["action"] as? String) == "ignored"
        }.count
        let notificationIgnoreRate = notificationCount > 0 ?
            Double(notificationIgnored) / Double(notificationCount) : 0.0
        let notificationClusteringIndex = computeNotificationClusteringIndex(notificationEvents)
        
        // Compute call summary
        let callEvents = filteredEvents.filter { $0.eventType == "call" }
        let callCount = callEvents.count
        let callIgnored = callEvents.filter {
            ($0.metrics["action"] as? String) == "ignored"
        }.count
        
        // Compute clipboard summary (tracked separately, not sent to Flux)
        let clipboardEvents = filteredEvents.filter { $0.eventType == "clipboard" }
        let clipboardCount = clipboardEvents.count
        let clipboardCopyCount = clipboardEvents.filter {
            ($0.metrics["action"] as? String) == "copy"
        }.count
        let clipboardPasteCount = clipboardEvents.filter {
            ($0.metrics["action"] as? String) == "paste"
        }.count
        let clipboardCutCount = clipboardEvents.filter {
            ($0.metrics["action"] as? String) == "cut"
        }.count
        
        // Calculate Clipboard Activity Rate
        // correction_rate and clipboard_activity_rate come from Flux

        // Compute behavioral metrics using Flux (Rust) - same as endSession()
        let (_, fluxMetrics, _) = computeBehavioralMetricsWithFlux(
            data: tempData,
            durationMs: duration,
            notificationCount: notificationCount,
            callCount: callCount
        )
        
        // Require Flux metrics - fail if not available
        guard let fluxMetrics = fluxMetrics else {
            throw NSError(
                domain: "BehaviorSDK",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Flux is required but metrics are not available for time range calculation"]
            )
        }
        
        // Extract behavioral metrics from Flux results (excluding typing summary)
        var behavioralMetrics: [String: Any] = [:]
        for (key, value) in fluxMetrics {
            if key != "typing_session_summary" {
                behavioralMetrics[key] = value
            }
        }
        
        // Extract typing session summary from Flux results (correction_rate and clipboard_activity_rate from Flux)
        let typingSessionSummary = fluxMetrics["typing_session_summary"] as? [String: Any] ?? [
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
            "correction_rate": 0.0,
            "clipboard_activity_rate": 0.0,
            "typing_metrics": [] as [[String: Any]]
        ]

        // Get motion data for the time range
        let allMotionData: [MotionSignalCollector.MotionDataPoint]
        if let _ = sessionDataEntry {
            // Session is still active - get current motion data from collector
            let currentMotionData = motionSignalCollector.getCurrentMotionData()
            allMotionData = currentMotionData.filter { dataPoint in
                do {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    guard let dataPointDate = formatter.date(from: dataPoint.timestamp) else { return false }
                    let dataPointTimeMs = Int64(dataPointDate.timeIntervalSince1970 * 1000)
                    return dataPointTimeMs >= startTimestampMs && dataPointTimeMs <= endTimestampMs
                } catch {
                    return false // Skip invalid timestamps
                }
            }
        } else {
            // Session has ended - motion data should be retrieved from stored data
            // For now, return empty list (motion data persistence can be added later)
            allMotionData = []
        }
        
        // Convert motion data to map format
        let motionDataList = allMotionData.map { dataPoint in
            [
                "timestamp": dataPoint.timestamp,
                "features": dataPoint.features
            ] as [String: Any]
        }
        
        // Get current device context and system state
        let currentScreenBrightness = getScreenBrightness()
        let currentOrientation = UIDevice.current.orientation
        let orientationStr: String
        switch currentOrientation {
        case .landscapeLeft, .landscapeRight:
            orientationStr = "landscape"
        default:
            orientationStr = "portrait"
        }
        
        // Build and return metrics map
        return [
            "behavioral_metrics": behavioralMetrics,
            "device_context": [
                "avg_screen_brightness": currentScreenBrightness,
                "start_orientation": orientationStr,
                "orientation_changes": sessionDataEntry?.orientationChangeCount ?? 0
            ] as [String: Any],
            "system_state": [
                "internet_state": isInternetConnected(),
                "do_not_disturb": isDoNotDisturbEnabled(),
                "charging": isCharging()
            ] as [String: Any],
            "activity_summary": [
                "total_events": filteredEvents.count,
                "app_switch_count": tempData.appSwitchCount
            ] as [String: Any],
            "notification_summary": [
                "notification_count": notificationCount,
                "notification_ignored": notificationIgnored,
                "notification_ignore_rate": notificationIgnoreRate,
                "notification_clustering_index": notificationClusteringIndex,
                "call_count": callCount,
                "call_ignored": callIgnored
            ] as [String: Any],
            "clipboard_summary": [
                "clipboard_count": clipboardCount,
                "clipboard_copy_count": clipboardCopyCount,
                "clipboard_paste_count": clipboardPasteCount,
                "clipboard_cut_count": clipboardCutCount
            ] as [String: Any],
            "typing_session_summary": typingSessionSummary,
            "motion_data": motionDataList
        ] as [String: Any]
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
        // Stop window calculations
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
