import UIKit
import CoreHaptics

/// Haptic feedback manager for enhanced user experience
class HapticManager {
    static let shared = HapticManager()

    private var hapticEngine: CHHapticEngine?
    private let logger = AppLogger.shared

    // Haptic generators (lighter weight for simple haptics)
    private let impactLightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let impactMediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {
        setupHapticEngine()
        prepareGenerators()
    }

    // MARK: - Setup

    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            logger.info("Device does not support haptics", category: "Haptics")
            return
        }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()

            hapticEngine?.stoppedHandler = { [weak self] reason in
                self?.logger.warning("Haptic engine stopped: \(reason.rawValue)", category: "Haptics")
                self?.restartEngine()
            }

            hapticEngine?.resetHandler = { [weak self] in
                self?.logger.info("Haptic engine reset", category: "Haptics")
                self?.restartEngine()
            }

            logger.info("Haptic engine initialized", category: "Haptics")
        } catch {
            logger.error("Failed to initialize haptic engine: \(error)", category: "Haptics")
        }
    }

    private func restartEngine() {
        do {
            try hapticEngine?.start()
        } catch {
            logger.error("Failed to restart haptic engine: \(error)", category: "Haptics")
        }
    }

    private func prepareGenerators() {
        impactLightGenerator.prepare()
        impactMediumGenerator.prepare()
        impactHeavyGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    // MARK: - Simple Haptics (UIFeedbackGenerator)

    /// Play success haptic (for successful operations)
    func success() {
        notificationGenerator.notificationOccurred(.success)
        logger.debug("Success haptic played", category: "Haptics")
    }

    /// Play warning haptic (for warnings or cautions)
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
        logger.debug("Warning haptic played", category: "Haptics")
    }

    /// Play error haptic (for errors or failures)
    func error() {
        notificationGenerator.notificationOccurred(.error)
        logger.debug("Error haptic played", category: "Haptics")
    }

    /// Play light impact (for subtle interactions)
    func impactLight() {
        impactLightGenerator.impactOccurred()
    }

    /// Play medium impact (for standard interactions)
    func impactMedium() {
        impactMediumGenerator.impactOccurred()
    }

    /// Play heavy impact (for significant interactions)
    func impactHeavy() {
        impactHeavyGenerator.impactOccurred()
    }

    /// Play selection haptic (for UI element selection)
    func selection() {
        selectionGenerator.selectionChanged()
    }

    // MARK: - Custom Haptics (CHHapticEngine)

    /// Play NFC scan success pattern
    func nfcScanSuccess() {
        guard let engine = hapticEngine else {
            success()  // Fallback to simple haptic
            return
        }

        // Create a custom pattern for NFC success
        let events = [
            // Quick tap
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            ),
            // Longer vibration
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0.1,
                duration: 0.2
            )
        ]

        playCustomPattern(events: events)
    }

    /// Play NFC scan failure pattern
    func nfcScanFailure() {
        guard let engine = hapticEngine else {
            error()  // Fallback to simple haptic
            return
        }

        // Create a custom pattern for NFC failure
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.15
            )
        ]

        playCustomPattern(events: events)
    }

    /// Play check-in success pattern (more celebratory)
    func checkinSuccess() {
        guard let engine = hapticEngine else {
            success()
            return
        }

        let events = [
            // Three quick taps
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0.08
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: 0.16
            )
        ]

        playCustomPattern(events: events)
    }

    /// Play button tap haptic
    func buttonTap() {
        impactLight()
    }

    /// Play toggle switch haptic
    func toggleSwitch() {
        selection()
    }

    /// Play scroll end haptic
    func scrollEnd() {
        impactMedium()
    }

    // MARK: - Custom Pattern Playback

    private func playCustomPattern(events: [CHHapticEvent]) {
        guard let engine = hapticEngine else { return }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            logger.debug("Custom haptic pattern played", category: "Haptics")
        } catch {
            logger.error("Failed to play custom haptic: \(error)", category: "Haptics")
        }
    }

    // MARK: - Utility

    /// Check if haptics are supported
    var isHapticsSupported: Bool {
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Enable/disable haptics (user preference)
    var isHapticsEnabled: Bool {
        get {
            // Default to true if not set
            return UserDefaults.standard.object(forKey: "haptics_enabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "haptics_enabled")
        }
    }

    // MARK: - Convenience Methods

    /// Play haptic only if enabled
    func playIfEnabled(_ hapticType: HapticType) {
        guard isHapticsEnabled else { return }

        switch hapticType {
        case .success:
            success()
        case .warning:
            warning()
        case .error:
            error()
        case .impactLight:
            impactLight()
        case .impactMedium:
            impactMedium()
        case .impactHeavy:
            impactHeavy()
        case .selection:
            selection()
        case .nfcScanSuccess:
            nfcScanSuccess()
        case .nfcScanFailure:
            nfcScanFailure()
        case .checkinSuccess:
            checkinSuccess()
        case .buttonTap:
            buttonTap()
        }
    }
}

// MARK: - Haptic Types

enum HapticType {
    case success
    case warning
    case error
    case impactLight
    case impactMedium
    case impactHeavy
    case selection
    case nfcScanSuccess
    case nfcScanFailure
    case checkinSuccess
    case buttonTap
}

// MARK: - SwiftUI View Extension

#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Add haptic feedback to a view action
    func hapticFeedback(_ hapticType: HapticType, trigger: some Equatable) -> some View {
        onChange(of: trigger) { _, _ in
            HapticManager.shared.playIfEnabled(hapticType)
        }
    }

    /// Add haptic feedback on button tap
    func buttonHaptic() -> some View {
        simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.buttonTap()
            }
        )
    }
}
#endif
