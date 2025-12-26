package ai.synheart.behavior

import android.app.Notification
import android.app.NotificationManager
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.time.Instant

/**
 * Collects notification signals (received and opened). Privacy: Only timing metrics, no
 * notification content or text.
 */
class NotificationCollector(private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private val receivedNotificationTimestamps =
            mutableMapOf<String, Long>() // notificationId -> timestamp
    // Track recent notifications by package to deduplicate rapid notifications from same app
    private val recentNotificationPackages =
            mutableMapOf<String, Long>() // packageName -> lastNotificationTime
    private val openedNotificationTimestamps = mutableListOf<Long>()
    private val handler = Handler(Looper.getMainLooper())
    private val notificationIgnoredThresholdMs = 30000L // 30 seconds
    // Track pending delayed tasks so we can cancel them if notification is opened
    private val pendingIgnoredTasks = mutableMapOf<String, Runnable>() // notificationId -> Runnable

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
    }

    private fun getIsoTimestamp(): String {
        return Instant.now().toString()
    }

    /**
     * Called when a notification is received. This should be called from
     * NotificationListenerService.onNotificationPosted.
     */
    fun onNotificationReceived(notificationId: String? = null, packageName: String? = null) {
        val now = System.currentTimeMillis()
        val id = notificationId ?: "notif_${now}"

        try {
            android.util.Log.d("NotificationCollector", "onNotificationReceived START")

            if (!config.enableAttentionSignals) {
                android.util.Log.d(
                        "NotificationCollector",
                        "enableAttentionSignals is false, returning"
                )
                return
            }

            // Check if we've already seen this notification recently (within last 5 seconds)
            // This prevents counting the same notification multiple times when Android updates it
            val lastSeenTime = receivedNotificationTimestamps[id]
            val isNewNotificationById = lastSeenTime == null || (now - lastSeenTime) >= 5000

            // Also check if we've seen a notification from this package very recently (within 1
            // second)
            // This prevents counting multiple notifications from the same app as separate
            // notifications
            // when apps like Telegram send multiple notifications rapidly
            val lastPackageNotificationTime = packageName?.let { recentNotificationPackages[it] }
            val isNewNotificationByPackage =
                    lastPackageNotificationTime == null ||
                            (now - lastPackageNotificationTime) >= 1000

            // Only emit if both checks pass (either new ID or new package notification)
            val isNewNotification = isNewNotificationById && isNewNotificationByPackage

            android.util.Log.d(
                    "NotificationCollector",
                    "Notification ID: $id, package: $packageName, lastSeenTime: $lastSeenTime, lastPackageTime: $lastPackageNotificationTime, isNew: $isNewNotification"
            )

            // Update package tracking
            packageName?.let { recentNotificationPackages[it] = now }

            android.util.Log.d("NotificationCollector", "Step 1: Getting timestamp")
            receivedNotificationTimestamps[id] = now

            // If this is a duplicate (notification updated), skip emitting event but update
            // timestamp
            if (!isNewNotification) {
                android.util.Log.d(
                        "NotificationCollector",
                        "Notification $id already tracked recently (${now - (lastSeenTime ?: 0)}ms ago), skipping duplicate event"
                )
                // Still need to cancel any existing ignored task and reschedule it
                pendingIgnoredTasks[id]?.let { task -> handler.removeCallbacks(task) }
                // Reschedule the ignored task
                val ignoredTask = Runnable {
                    if (receivedNotificationTimestamps.containsKey(id)) {
                        receivedNotificationTimestamps.remove(id)
                        pendingIgnoredTasks.remove(id)
                        eventHandler?.invoke(
                                BehaviorEvent(
                                        sessionId = "current",
                                        timestamp = getIsoTimestamp(),
                                        eventType = "notification",
                                        metrics = mapOf("action" to "ignored")
                                )
                        )
                    } else {
                        pendingIgnoredTasks.remove(id)
                    }
                }
                pendingIgnoredTasks[id] = ignoredTask
                handler.postDelayed(ignoredTask, notificationIgnoredThresholdMs)
                return
            }

            android.util.Log.d("NotificationCollector", "Step 2: Cleaning old notifications")
            // Keep only last 100 notifications
            if (receivedNotificationTimestamps.size > 100) {
                val oldest = receivedNotificationTimestamps.minByOrNull { it.value }?.key
                oldest?.let { receivedNotificationTimestamps.remove(it) }
            }

            android.util.Log.d("NotificationCollector", "Step 3: Creating event")
            val event =
                    BehaviorEvent(
                            sessionId = "current",
                            timestamp = getIsoTimestamp(),
                            eventType = "notification",
                            metrics = mapOf("action" to "received")
                    )

            android.util.Log.d(
                    "NotificationCollector",
                    "Step 4: Event created, eventHandler null: ${eventHandler == null}"
            )

            if (eventHandler == null) {
                android.util.Log.e(
                        "NotificationCollector",
                        "ERROR: eventHandler is NULL! Event will not be emitted."
                )
            } else {
                android.util.Log.d("NotificationCollector", "Step 5: Calling eventHandler")
                eventHandler?.invoke(event)
                android.util.Log.d("NotificationCollector", "Step 6: eventHandler invoked")
            }
        } catch (e: Exception) {
            android.util.Log.e(
                    "NotificationCollector",
                    "EXCEPTION in onNotificationReceived: ${e.message}",
                    e
            )
        }

        // Schedule check for ignored notification (30 seconds)
        // Store the Runnable so we can cancel it if the notification is opened
        val ignoredTask = Runnable {
            if (receivedNotificationTimestamps.containsKey(id)) {
                // Notification was not opened within 30 seconds, mark as ignored
                receivedNotificationTimestamps.remove(id)
                pendingIgnoredTasks.remove(id) // Clean up
                eventHandler?.invoke(
                        BehaviorEvent(
                                sessionId = "current",
                                timestamp = getIsoTimestamp(),
                                eventType = "notification",
                                metrics = mapOf("action" to "ignored")
                        )
                )
            } else {
                // Notification was opened, just clean up
                pendingIgnoredTasks.remove(id)
            }
        }
        pendingIgnoredTasks[id] = ignoredTask
        handler.postDelayed(ignoredTask, notificationIgnoredThresholdMs)
    }

    /**
     * Called when a notification is opened/tapped. This should be called from
     * NotificationListenerService.onNotificationRemoved when the removal reason is REASON_CLICK.
     */
    fun onNotificationOpened(notificationId: String? = null) {
        if (!config.enableAttentionSignals) return

        val now = System.currentTimeMillis()
        openedNotificationTimestamps.add(now)

        // Keep only last 100 notifications
        while (openedNotificationTimestamps.size > 100) {
            openedNotificationTimestamps.removeFirst()
        }

        // Cancel the pending "ignored" task if notification is opened before 30 seconds
        notificationId?.let { id ->
            // Remove from received list
            receivedNotificationTimestamps.remove(id)

            // Cancel the delayed "ignored" task if it exists
            pendingIgnoredTasks[id]?.let { task ->
                handler.removeCallbacks(task)
                pendingIgnoredTasks.remove(id)
                android.util.Log.d(
                        "NotificationCollector",
                        "Cancelled pending 'ignored' task for notification: $id"
                )
            }
        }

        android.util.Log.d("NotificationCollector", "NOTIFICATION OPENED!")

        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = getIsoTimestamp(),
                        eventType = "notification",
                        metrics = mapOf("action" to "opened")
                )
        )
    }

    fun dispose() {
        // Cancel all pending tasks
        pendingIgnoredTasks.values.forEach { task -> handler.removeCallbacks(task) }
        receivedNotificationTimestamps.clear()
        recentNotificationPackages.clear()
        openedNotificationTimestamps.clear()
        pendingIgnoredTasks.clear()
    }
}

/**
 * NotificationListenerService implementation for detecting notifications.
 *
 * Note: This requires the BIND_NOTIFICATION_LISTENER_SERVICE permission and the user must enable
 * notification access in system settings.
 */
class SynheartNotificationListenerService : NotificationListenerService() {

    companion object {
        private var notificationCollector: NotificationCollector? = null

        fun setNotificationCollector(collector: NotificationCollector?) {
            android.util.Log.d(
                    "SynheartNotificationListenerService",
                    "setNotificationCollector called: collector=${collector != null}, hashCode=${collector?.hashCode()}"
            )
            notificationCollector = collector
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        // Track all posted notifications (privacy: no content, only timing)
        if (sbn != null) {
            // Filter out notifications that shouldn't be tracked
            if (!shouldTrackNotification(sbn)) {
                android.util.Log.d(
                        "SynheartNotificationListenerService",
                        "onNotificationPosted: Filtered out notification from ${sbn.packageName}"
                )
                return
            }

            val notificationId = sbn.key // Use notification key as ID
            val packageName = sbn.packageName
            // Also log tag and id for debugging
            val tag = sbn.tag
            val id = sbn.id
            android.util.Log.d(
                    "SynheartNotificationListenerService",
                    "onNotificationPosted: key=$notificationId, tag=$tag, id=$id, package=$packageName"
            )
            notificationCollector?.onNotificationReceived(notificationId, packageName)
        } else {
            android.util.Log.w(
                    "SynheartNotificationListenerService",
                    "onNotificationPosted: sbn is null"
            )
        }
    }

    /**
     * Determines if a notification should be tracked. Filters out:
     * - System notifications (android, com.android.systemui)
     * - Silent notifications (LOW or MIN importance)
     * - Persistent/ongoing notifications
     * - Group summary notifications (to avoid duplicates)
     * - Notifications from the app itself (to avoid self-tracking)
     */
    private fun shouldTrackNotification(sbn: StatusBarNotification): Boolean {
        val packageName = sbn.packageName
        val notification = sbn.notification

        // Filter out system notifications
        if (packageName == "android" || packageName == "com.android.systemui") {
            return false
        }

        // Filter out group summary notifications (apps like Telegram, WhatsApp send these)
        // Group summaries cause duplicate onNotificationPosted calls
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) {
            android.util.Log.d(
                    "SynheartNotificationListenerService",
                    "Filtered out group summary notification from $packageName"
            )
            return false
        }

        // Filter out notifications from this app itself (to avoid self-tracking)
        try {
            val notificationPackageName = packageName
            val servicePackageName = this.packageName
            if (notificationPackageName == servicePackageName) {
                android.util.Log.d(
                        "SynheartNotificationListenerService",
                        "Filtered out self-notification from $notificationPackageName"
                )
                return false
            }
        } catch (e: Exception) {
            // If we can't determine package name, allow it (better to track than miss)
            android.util.Log.w(
                    "SynheartNotificationListenerService",
                    "Could not determine package name: ${e.message}"
            )
        }

        // Filter out silent notifications (LOW or MIN importance)
        // Get importance from RankingMap
        val ranking = NotificationListenerService.Ranking()
        val rankingMap = getCurrentRanking()
        if (rankingMap != null && rankingMap.getRanking(sbn.key, ranking)) {
            val importance = ranking.importance
            if (importance == NotificationManager.IMPORTANCE_LOW ||
                            importance == NotificationManager.IMPORTANCE_MIN
            ) {
                return false
            }
        }

        // Filter out persistent/ongoing notifications
        if ((notification.flags and Notification.FLAG_ONGOING_EVENT) != 0) {
            return false
        }

        return true
    }

    override fun onNotificationRemoved(
            sbn: StatusBarNotification?,
            rankingMap: RankingMap?,
            reason: Int
    ) {
        super.onNotificationRemoved(sbn, rankingMap, reason)
        // REASON_CLICK = 1 means user clicked the notification
        if (reason == NotificationListenerService.REASON_CLICK && sbn != null) {
            // Only track if we would have tracked the notification when it was posted
            if (shouldTrackNotification(sbn)) {
                val notificationId = sbn.key
                notificationCollector?.onNotificationOpened(notificationId)
            }
        }
    }
}
