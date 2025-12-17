import Foundation
import UserNotifications

/// Collects notification signals (received and opened).
/// Privacy: Only timing metrics, no notification content or text.
class NotificationCollector: NSObject, UNUserNotificationCenterDelegate {
    
    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var receivedNotificationTimestamps: [Double] = []
    private var openedNotificationTimestamps: [Double] = []
    
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
            if granted {
                print("NotificationCollector: Notification permission granted")
            } else {
                print("NotificationCollector: Notification permission denied")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    /// Called when a notification is delivered while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        onNotificationReceived()
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Called when user taps/opens a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        onNotificationOpened()
        completionHandler()
    }
    
    private func onNotificationReceived() {
        guard config.enableAttentionSignals else { return }
        
        let now = Date().timeIntervalSince1970 * 1000 // milliseconds
        receivedNotificationTimestamps.append(now)
        
        // Keep only last 100 notifications
        if receivedNotificationTimestamps.count > 100 {
            receivedNotificationTimestamps.removeFirst()
        }
        
        print("NotificationCollector: NOTIFICATION RECEIVED!")
        
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(now),
            type: "notificationReceived",
            payload: [
                "timestamp": now
            ]
        ))
    }
    
    private func onNotificationOpened() {
        guard config.enableAttentionSignals else { return }
        
        let now = Date().timeIntervalSince1970 * 1000 // milliseconds
        openedNotificationTimestamps.append(now)
        
        // Keep only last 100 notifications
        if openedNotificationTimestamps.count > 100 {
            openedNotificationTimestamps.removeFirst()
        }
        
        print("NotificationCollector: NOTIFICATION OPENED!")
        
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(now),
            type: "notificationOpened",
            payload: [
                "timestamp": now
            ]
        ))
    }
    
    func dispose() {
        receivedNotificationTimestamps.removeAll()
        openedNotificationTimestamps.removeAll()
        UNUserNotificationCenter.current().delegate = nil
    }
}

