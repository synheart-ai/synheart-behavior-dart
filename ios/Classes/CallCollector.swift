import Foundation
import CoreTelephony

/// Collects phone call signals (incoming, answered, ignored).
/// Privacy: Only timing metrics, no phone numbers or contact information.
class CallCollector {
    
    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var callCenter: CTCallCenter?
    private var incomingCallStartTime: Double = 0
    private var isCallActive = false
    private let callIgnoredThresholdMs: Double = 30000.0 // 30 seconds
    
    init(config: BehaviorConfig) {
        self.config = config
    }
    
    func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
    }
    
    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
    }
    
    func startMonitoring() {
        guard config.enableAttentionSignals else {
            return
        }
        
        callCenter = CTCallCenter()
        
        callCenter?.callEventHandler = { [weak self] call in
            guard let self = self else { return }
            
            // CTCall.callState is a String, not an enum
            let callState = call.callState
            
            if callState == CTCallStateIncoming {
                // Incoming call detected
                self.incomingCallStartTime = Date().timeIntervalSince1970 * 1000
                self.isCallActive = false
                self.onIncomingCall()
                
            } else if callState == CTCallStateConnected || callState == CTCallStateDialing {
                // Call answered or dialing
                if self.incomingCallStartTime > 0 {
                    self.onCallAnswered()
                }
                self.isCallActive = true
                
            } else if callState == CTCallStateDisconnected {
                // Call ended or ignored
                if self.incomingCallStartTime > 0 && !self.isCallActive {
                    // Call was never answered, so it's ignored
                    let duration = Date().timeIntervalSince1970 * 1000 - self.incomingCallStartTime
                    // Count all ignored calls, regardless of duration
                    // (Very short calls < 1 second might be accidental, but we'll track them anyway)
                    if duration >= 1000 { // Only ignore calls that lasted at least 1 second (to filter out accidental/system calls)
                        self.onCallIgnored()
                    }
                }
                self.incomingCallStartTime = 0
                self.isCallActive = false
            }
        }
    }
    
    func stopMonitoring() {
        callCenter?.callEventHandler = nil
        callCenter = nil
    }
    
    private func onIncomingCall() {
        // Note: We don't emit an event for incoming calls, only for answered/ignored
        // This matches the requirement that calls should only have "action": "ignored" (or answered)
    }
    
    private func onCallAnswered() {
        let event = BehaviorEvent(
            sessionId: "current",
            eventType: "call",
            metrics: [
                "action": "answered"
            ]
        )
        if eventHandler != nil {
            eventHandler?(event)
        }
        incomingCallStartTime = 0 // Reset to prevent duplicate events
    }
    
    private func onCallIgnored() {
        let event = BehaviorEvent(
            sessionId: "current",
            eventType: "call",
            metrics: [
                "action": "ignored"
            ]
        )
        if eventHandler != nil {
            eventHandler?(event)
        }
        incomingCallStartTime = 0 // Reset to prevent duplicate events
    }
    
    func dispose() {
        stopMonitoring()
    }
}
