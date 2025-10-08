import SwiftUI
import UIKit

/// Accessibility helpers and utilities
class AccessibilityHelper {
    static let shared = AccessibilityHelper()

    private init() {}

    // MARK: - Accessibility Checks

    /// Check if VoiceOver is running
    var isVoiceOverRunning: Bool {
        return UIAccessibility.isVoiceOverRunning
    }

    /// Check if Reduce Motion is enabled
    var isReduceMotionEnabled: Bool {
        return UIAccessibility.isReduceMotionEnabled
    }

    /// Check if Bold Text is enabled
    var isBoldTextEnabled: Bool {
        return UIAccessibility.isBoldTextEnabled
    }

    /// Check if Increase Contrast is enabled
    var isIncreaseContrastEnabled: Bool {
        return UIAccessibility.isDarkerSystemColorsEnabled
    }

    /// Check if Reduce Transparency is enabled
    var isReduceTransparencyEnabled: Bool {
        return UIAccessibility.isReduceTransparencyEnabled
    }

    // MARK: - Announcements

    /// Post an accessibility announcement
    func announce(_ message: String, priority: AnnouncementPriority = .normal) {
        let notification: UIAccessibility.Notification

        switch priority {
        case .low:
            notification = .announcement
        case .normal:
            notification = .announcement
        case .high:
            notification = .screenChanged
        }

        UIAccessibility.post(notification: notification, argument: message)
        AppLogger.shared.debug("Accessibility announcement: \(message)", category: "Accessibility")
    }

    /// Announce a screen change
    func announceScreenChange(title: String) {
        UIAccessibility.post(notification: .screenChanged, argument: title)
    }

    /// Announce a layout change
    func announceLayoutChange(message: String) {
        UIAccessibility.post(notification: .layoutChanged, argument: message)
    }

    // MARK: - Focus Management

    /// Request accessibility focus on a specific element
    func requestFocus(on element: Any) {
        UIAccessibility.post(notification: .layoutChanged, argument: element)
    }

    enum AnnouncementPriority {
        case low, normal, high
    }
}

// MARK: - SwiftUI View Extensions

extension View {
    /// Add accessibility label with automatic localization
    func accessibilityLabel(_ key: LocalizedStringKey) -> some View {
        self.accessibilityLabel(Text(key))
    }

    /// Add accessibility hint
    func accessibilityHint(_ key: LocalizedStringKey) -> some View {
        self.accessibilityHint(Text(key))
    }

    /// Add accessibility value
    func accessibilityValue(_ value: String) -> some View {
        self.accessibilityValue(Text(value))
    }

    /// Mark as button with proper traits
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint.map { Text($0) } ?? Text(""))
    }

    /// Mark as header
    func accessibleHeader(_ label: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isHeader)
    }

    /// Group accessibility elements
    func accessibilityGroup(label: String) -> some View {
        self
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }

    /// Add custom accessibility action
    func accessibilityCustomAction(
        named name: String,
        action: @escaping () -> Bool
    ) -> some View {
        self.accessibilityAction(named: name) {
            _ = action()
        }
    }

    /// Support dynamic type scaling
    func dynamicTypeSupport(min: DynamicTypeSize = .xSmall, max: DynamicTypeSize = .xxxLarge) -> some View {
        self.dynamicTypeSize(min...max)
    }

    /// High contrast mode support
    func highContrastSupport<V: View>(
        @ViewBuilder alternative: () -> V
    ) -> some View {
        @Environment(\.colorSchemeContrast) var contrast

        return Group {
            if contrast == .increased {
                alternative()
            } else {
                self
            }
        }
    }
}

// MARK: - Accessible Components

/// Accessible button with haptic feedback
struct AccessibleButton<Label: View>: View {
    let action: () -> Void
    let label: Label
    let accessibilityLabel: String
    let accessibilityHint: String?

    @Environment(\.colorSchemeContrast) var contrast

    init(
        _ accessibilityLabel: String,
        hint: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = hint
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            action()
        }) {
            label
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint.map { Text($0) } ?? Text(""))
        .accessibilityAddTraits(.isButton)
        .dynamicTypeSupport()
    }
}

/// Accessible toggle switch
struct AccessibleToggle: View {
    @Binding var isOn: Bool
    let label: String
    let hint: String?

    init(_ label: String, isOn: Binding<Bool>, hint: String? = nil) {
        self.label = label
        self._isOn = isOn
        self.hint = hint
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .accessibilityLabel(label)
            .accessibilityHint(hint.map { Text($0) } ?? Text(""))
            .accessibilityValue(isOn ? "On" : "Off")
            .onChange(of: isOn) { _, newValue in
                HapticManager.shared.toggleSwitch()
                AccessibilityHelper.shared.announce(
                    "\(label) \(newValue ? "on" : "off")",
                    priority: .low
                )
            }
            .dynamicTypeSupport()
    }
}

/// Accessible text field
struct AccessibleTextField: View {
    @Binding var text: String
    let label: String
    let placeholder: String
    let hint: String?

    init(_ label: String, text: Binding<String>, placeholder: String = "", hint: String? = nil) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.hint = hint
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .accessibilityLabel(label)
            .accessibilityHint(hint.map { Text($0) } ?? Text(""))
            .accessibilityValue(text.isEmpty ? "Empty" : text)
            .dynamicTypeSupport()
    }
}

/// Accessible list row with swipe actions
struct AccessibleListRow<Content: View>: View {
    let content: Content
    let accessibilityLabel: String
    let deleteAction: (() -> Void)?
    let editAction: (() -> Void)?

    init(
        _ accessibilityLabel: String,
        deleteAction: (() -> Void)? = nil,
        editAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.deleteAction = deleteAction
        self.editAction = editAction
        self.content = content()
    }

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .if(deleteAction != nil) { view in
                view.accessibilityCustomAction(named: "Delete") {
                    deleteAction?()
                    return true
                }
            }
            .if(editAction != nil) { view in
                view.accessibilityCustomAction(named: "Edit") {
                    editAction?()
                    return true
                }
            }
            .dynamicTypeSupport()
    }
}

/// Loading indicator with accessibility support
struct AccessibleLoadingView: View {
    let message: String

    init(_ message: String = "Loading") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            AccessibilityHelper.shared.announce(message, priority: .low)
        }
    }
}

/// Error view with accessibility support
struct AccessibleErrorView: View {
    let error: Error
    let retryAction: () -> Void

    init(error: Error, retry: @escaping () -> Void) {
        self.error = error
        self.retryAction = retry
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
                .accessibilityHidden(true)

            Text("Error")
                .font(.headline)
                .accessibleHeader("Error")

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            AccessibleButton("Retry", hint: "Tap to try again") {
                retryAction()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .onAppear {
            AccessibilityHelper.shared.announce(
                "Error: \(error.localizedDescription)",
                priority: .high
            )
        }
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Color Extensions for Accessibility

extension Color {
    /// Get color with high contrast variant
    static func accessible(light: Color, dark: Color, highContrast: Color? = nil) -> Color {
        @Environment(\.colorScheme) var colorScheme
        @Environment(\.colorSchemeContrast) var contrast

        if contrast == .increased, let highContrast = highContrast {
            return highContrast
        }

        return colorScheme == .dark ? dark : light
    }
}
