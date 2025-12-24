import Foundation
import UserNotifications

/// Collects notification signals (received and opened).
/// Privacy: Only timing metrics, no notification content or text.
class NotificationCollector: NSObject, UNUserNotificationCenterDelegate {
    
    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var receivedNotificationTimestamps: [String: Double] = [:] // notificationId -> timestamp
    private var openedNotificationTimestamps: [Double] = []
    private let notificationIgnoredThresholdMs: Double = 30000.0 // 30 seconds
    // Track pending delayed tasks so we can cancel them if notification is opened
    private var pendingIgnoredTasks: [String: DispatchWorkItem] = [:] // notificationId -> DispatchWorkItem
    
    init(config: BehaviorConfig) {
        self.config = config
        super.init()
    }
    
    func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
    }
    
    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
    }
    
    func startMonitoring() {
        guard config.enableAttentionSignals else { return }
        
        // Set this class as the notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions (if not already granted)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            // Permission request completed
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Called when a notification is delivered while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let notificationId = notification.request.identifier
        onNotificationReceived(notificationId: notificationId)
        // Show notification even when app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    /// Called when user taps/opens a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notificationId = response.notification.request.identifier
        onNotificationOpened(notificationId: notificationId)
        completionHandler()
    }
    
    private func onNotificationReceived(notificationId: String? = nil) {
        guard config.enableAttentionSignals else { return }
        
        let now = Date().timeIntervalSince1970 * 1000 // milliseconds
        let id = notificationId ?? "notif_\(Int64(now))"
        receivedNotificationTimestamps[id] = now
        
        // Keep only last 100 notifications
        if receivedNotificationTimestamps.count > 100 {
            let oldest = receivedNotificationTimestamps.min(by: { $0.value < $1.value })?.key
            oldest.map { receivedNotificationTimestamps.removeValue(forKey: $0) }
        }
        
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            eventType: "notification",
            metrics: [
                "action": "received"
            ]
        ))
        
        // Schedule check for ignored notification (30 seconds)
        // Store the DispatchWorkItem so we can cancel it if the notification is opened
        let ignoredTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.receivedNotificationTimestamps.keys.contains(id) {
                // Notification was not opened within 30 seconds, mark as ignored
                self.receivedNotificationTimestamps.removeValue(forKey: id)
                self.pendingIgnoredTasks.removeValue(forKey: id) // Clean up
                self.eventHandler?(BehaviorEvent(
                    sessionId: "current",
                    eventType: "notification",
                    metrics: [
                        "action": "ignored"
                    ]
                ))
            } else {
                // Notification was opened, just clean up
                self.pendingIgnoredTasks.removeValue(forKey: id)
            }
        }
        pendingIgnoredTasks[id] = ignoredTask
        DispatchQueue.main.asyncAfter(deadline: .now() + notificationIgnoredThresholdMs / 1000.0, execute: ignoredTask)
    }
    
    private func onNotificationOpened(notificationId: String? = nil) {
        guard config.enableAttentionSignals else { return }
        
        let now = Date().timeIntervalSince1970 * 1000 // milliseconds
        openedNotificationTimestamps.append(now)
        
        // Keep only last 100 notifications
        if openedNotificationTimestamps.count > 100 {
            openedNotificationTimestamps.removeFirst()
        }
        
        // Cancel the pending "ignored" task if notification is opened before 30 seconds
        if let id = notificationId {
            // Remove from received list
            receivedNotificationTimestamps.removeValue(forKey: id)
            
            // Cancel the delayed "ignored" task if it exists
            if let task = pendingIgnoredTasks[id] {
                task.cancel()
                pendingIgnoredTasks.removeValue(forKey: id)
            }
        }
        
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            eventType: "notification",
            metrics: [
                "action": "opened"
            ]
        ))
    }
    
    func dispose() {
        // Cancel all pending tasks
        pendingIgnoredTasks.values.forEach { $0.cancel() }
        receivedNotificationTimestamps.removeAll()
        openedNotificationTimestamps.removeAll()
        pendingIgnoredTasks.removeAll()
        UNUserNotificationCenter.current().delegate = nil
    }
}

