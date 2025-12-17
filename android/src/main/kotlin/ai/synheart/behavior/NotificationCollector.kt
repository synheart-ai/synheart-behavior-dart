package ai.synheart.behavior

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Collects notification signals (received and opened).
 * Privacy: Only timing metrics, no notification content or text.
 */
class NotificationCollector(private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private val receivedNotificationTimestamps = mutableListOf<Long>()
    private val openedNotificationTimestamps = mutableListOf<Long>()

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
    }

    /**
     * Called when a notification is received.
     * This should be called from NotificationListenerService.onNotificationPosted.
     */
    fun onNotificationReceived() {
        if (!config.enableAttentionSignals) return

        val now = System.currentTimeMillis()
        receivedNotificationTimestamps.add(now)

        // Keep only last 100 notifications
        while (receivedNotificationTimestamps.size > 100) {
            receivedNotificationTimestamps.removeFirst()
        }

        android.util.Log.d("NotificationCollector", "NOTIFICATION RECEIVED!")

        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current",
                timestamp = now,
                type = "notificationReceived",
                payload = mapOf(
                    "timestamp" to now,
                )
            )
        )
    }

    /**
     * Called when a notification is opened/tapped.
     * This should be called from NotificationListenerService.onNotificationRemoved
     * when the removal reason is REASON_CLICK.
     */
    fun onNotificationOpened() {
        if (!config.enableAttentionSignals) return

        val now = System.currentTimeMillis()
        openedNotificationTimestamps.add(now)

        // Keep only last 100 notifications
        while (openedNotificationTimestamps.size > 100) {
            openedNotificationTimestamps.removeFirst()
        }

        android.util.Log.d("NotificationCollector", "NOTIFICATION OPENED!")

        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current",
                timestamp = now,
                type = "notificationOpened",
                payload = mapOf(
                    "timestamp" to now,
                )
            )
        )
    }

    fun dispose() {
        receivedNotificationTimestamps.clear()
        openedNotificationTimestamps.clear()
    }
}

/**
 * NotificationListenerService implementation for detecting notifications.
 * 
 * Note: This requires the BIND_NOTIFICATION_LISTENER_SERVICE permission
 * and the user must enable notification access in system settings.
 */
class SynheartNotificationListenerService : NotificationListenerService() {
    
    companion object {
        private var notificationCollector: NotificationCollector? = null
        
        fun setNotificationCollector(collector: NotificationCollector?) {
            notificationCollector = collector
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        // Track all posted notifications (privacy: no content, only timing)
        if (sbn != null) {
            notificationCollector?.onNotificationReceived()
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?, rankingMap: RankingMap?, reason: Int) {
        super.onNotificationRemoved(sbn, rankingMap, reason)
        // REASON_CLICK = 1 means user clicked the notification
        if (reason == NotificationListenerService.REASON_CLICK) {
            notificationCollector?.onNotificationOpened()
        }
    }
}

