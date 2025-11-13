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
                selector: #selector(textViewDidChange(_:)),
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

    @objc private func textViewDidChange(_ notification: Notification) {
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

        // Calculate inter-key latency
        if lastKeystrokeTime > 0 {
            let latency = now - lastKeystrokeTime
            emitTypingCadence(interKeyLatency: latency)
        }

        lastKeystrokeTime = now
    }

    private func emitTypingCadence(interKeyLatency: Double) {
        let now = Date().timeIntervalSince1970 * 1000
        let recentKeys = keystrokeTimestamps.filter { $0 > now - 5000 }

        let cadence: Double
        if recentKeys.count > 1 {
            let timeSpan = recentKeys.last! - recentKeys.first!
            cadence = timeSpan > 0 ? Double(recentKeys.count - 1) * 1000.0 / timeSpan : 0.0
        } else {
            cadence = 0.0
        }

        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(now),
            type: "typingCadence",
            payload: [
                "cadence": cadence,
                "inter_key_latency": interKeyLatency,
                "keys_in_window": recentKeys.count
            ]
        ))
    }

    private func emitTypingBurst(burstLength: Int) {
        guard burstLength >= 3 else { return } // Only emit significant bursts

        var recentLatencies: [Double] = []
        let count = min(keystrokeTimestamps.count, burstLength)
        for i in 1..<count {
            recentLatencies.append(keystrokeTimestamps[i] - keystrokeTimestamps[i - 1])
        }

        let avgLatency = recentLatencies.isEmpty ? 0.0 : recentLatencies.reduce(0, +) / Double(recentLatencies.count)

        let variance: Double
        if recentLatencies.count > 1 {
            let mean = avgLatency
            let squaredDiffs = recentLatencies.map { pow($0 - mean, 2) }
            variance = squaredDiffs.reduce(0, +) / Double(squaredDiffs.count)
        } else {
            variance = 0.0
        }

        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "typingBurst",
            payload: [
                "burst_length": burstLength,
                "inter_key_latency": avgLatency,
                "variance": variance
            ]
        ))
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
