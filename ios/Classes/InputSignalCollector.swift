import Foundation
import UIKit

/// Collects input signals like keystroke timing.
/// Privacy: NO text content is collected, only timing metrics.
class InputSignalCollector: NSObject, UITextFieldDelegate, UITextViewDelegate {

    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var keystrokeTimestamps: [Double] = []
    private var lastKeystrokeTime: Double = 0
    private var currentBurstLength: Int = 0
    private let maxBurstGap: Double = 2.0 // 2 seconds

    private var monitoredTextFields: [UITextField] = []
    private var monitoredTextViews: [UITextView] = []

    init(config: BehaviorConfig) {
        self.config = config
        super.init()
        setupNotifications()
    }

    func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
    }

    func attachToView(_ view: UIView) {
        guard config.enableInputSignals else { return }

        if let textField = view as? UITextField {
            textField.delegate = self
            monitoredTextFields.append(textField)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(textFieldDidChange(_:)),
                name: UITextField.textDidChangeNotification,
                object: textField
            )
        } else if let textView = view as? UITextView {
            textView.delegate = self
            monitoredTextViews.append(textView)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(textViewNotificationDidChange(_:)),
                name: UITextView.textDidChangeNotification,
                object: textView
            )
        }

        // Recursively attach to subviews
        for subview in view.subviews {
            attachToView(subview)
        }
    }

    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
    }

    func dispose() {
        NotificationCenter.default.removeObserver(self)
        keystrokeTimestamps.removeAll()
        monitoredTextFields.removeAll()
        monitoredTextViews.removeAll()
    }

    private func setupNotifications() {
        // Monitor all text input changes globally
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: UITextField.textDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: UITextView.textDidChangeNotification,
            object: nil
        )
    }

    @objc private func textFieldDidChange(_ notification: Notification) {
        onKeystroke()
    }

    @objc private func textViewNotificationDidChange(_ notification: Notification) {
        onKeystroke()
    }

    @objc private func textDidChange(_ notification: Notification) {
        onKeystroke()
    }

    private func onKeystroke() {
        let now = Date().timeIntervalSince1970 * 1000 // milliseconds
        keystrokeTimestamps.append(now)

        // Keep only last 100 keystrokes
        if keystrokeTimestamps.count > 100 {
            keystrokeTimestamps.removeFirst()
        }

        // Check if part of current burst
        if lastKeystrokeTime > 0 && (now - lastKeystrokeTime) < maxBurstGap * 1000 {
            currentBurstLength += 1
        } else {
            // New burst
            if currentBurstLength > 0 {
                emitTypingBurst(burstLength: currentBurstLength)
            }
            currentBurstLength = 1
        }

        // Calculate inter-key latency and emit typing cadence
        // For first keystroke, use a default latency of 0 (will be counted but with 0 latency)
        if lastKeystrokeTime > 0 {
            let latency = now - lastKeystrokeTime
            emitTypingCadence(interKeyLatency: latency)
        } else {
            // First keystroke: emit with 0 latency so it's counted
            emitTypingCadence(interKeyLatency: 0)
        }

        lastKeystrokeTime = now
    }

    private func emitTypingCadence(interKeyLatency: Double) {
        // In new model, keystrokes are tracked as tap events
        // Estimate tap duration (typically 50-150ms for keyboard taps)
        let estimatedTapDuration = Int(max(50, min(150, interKeyLatency)))

        eventHandler?(BehaviorEvent(
            sessionId: "current",
            eventType: "tap",
            metrics: [
                "tap_duration_ms": estimatedTapDuration,
                "long_press": false
            ]
        ))
    }

    private func emitTypingBurst(burstLength: Int) {
        // Bursts are now tracked as individual tap events
        // No need to emit separate burst events
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Text field focused
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        // Text field unfocused
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        // Text view focused
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        // Text view unfocused
    }
}
