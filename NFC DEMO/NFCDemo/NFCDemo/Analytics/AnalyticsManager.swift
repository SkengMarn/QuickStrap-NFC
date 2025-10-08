import Foundation

/// Analytics and crash reporting manager
/// Provides a unified interface for analytics providers
class AnalyticsManager {
    static let shared = AnalyticsManager()

    private let logger = AppLogger.shared
    private var providers: [AnalyticsProvider] = []

    private init() {
        setupProviders()
    }

    // MARK: - Setup

    private func setupProviders() {
        // Add analytics providers
        #if !DEBUG
        // In production, initialize real analytics providers
        // providers.append(FirebaseAnalyticsProvider())
        // providers.append(MixpanelProvider())
        #else
        // In debug, use console logging provider
        providers.append(ConsoleAnalyticsProvider())
        #endif

        logger.info("Analytics initialized with \(providers.count) provider(s)", category: "Analytics")
    }

    /// Add a custom analytics provider
    func addProvider(_ provider: AnalyticsProvider) {
        providers.append(provider)
        logger.info("Added analytics provider: \(type(of: provider))", category: "Analytics")
    }

    // MARK: - User Properties

    /// Set user ID
    func setUserId(_ userId: String) {
        providers.forEach { $0.setUserId(userId) }
        logger.debug("Set user ID: \(userId)", category: "Analytics")
    }

    /// Set user property
    func setUserProperty(_ key: String, value: String) {
        providers.forEach { $0.setUserProperty(key, value: value) }
        logger.debug("Set user property: \(key) = \(value)", category: "Analytics")
    }

    /// Clear user data (on logout)
    func clearUserData() {
        providers.forEach { $0.clearUserData() }
        logger.info("Cleared user data", category: "Analytics")
    }

    // MARK: - Event Tracking

    /// Track an event
    func trackEvent(_ event: AnalyticsEvent) {
        providers.forEach { $0.trackEvent(event) }
        logger.debug("Tracked event: \(event.name)", category: "Analytics")
    }

    /// Track screen view
    func trackScreen(_ screenName: String, parameters: [String: Any] = [:]) {
        let event = AnalyticsEvent(
            name: "screen_view",
            category: .navigation,
            parameters: ["screen_name": screenName].merging(parameters) { _, new in new }
        )
        trackEvent(event)
    }

    // MARK: - Crash Reporting

    /// Log non-fatal error
    func logError(_ error: Error, additionalInfo: [String: Any] = [:]) {
        providers.forEach { $0.logError(error, additionalInfo: additionalInfo) }
        logger.error("Logged error: \(error.localizedDescription)", category: "Analytics")
    }

    /// Log fatal crash
    func logCrash(_ error: Error, stackTrace: String? = nil) {
        providers.forEach { $0.logCrash(error, stackTrace: stackTrace) }
        logger.critical("Logged crash: \(error.localizedDescription)", category: "Analytics")
    }

    /// Add breadcrumb for crash context
    func addBreadcrumb(_ message: String, category: String = "general", level: BreadcrumbLevel = .info) {
        let breadcrumb = Breadcrumb(message: message, category: category, level: level)
        providers.forEach { $0.addBreadcrumb(breadcrumb) }
    }

    // MARK: - Performance Monitoring

    /// Start performance trace
    func startTrace(_ name: String) -> PerformanceTrace {
        let trace = PerformanceTrace(name: name)
        providers.forEach { $0.startTrace(trace) }
        return trace
    }

    /// Stop performance trace
    func stopTrace(_ trace: PerformanceTrace) {
        trace.stop()
        providers.forEach { $0.stopTrace(trace) }
        logger.debug("Performance trace '\(trace.name)' took \(trace.duration ?? 0)s", category: "Analytics")
    }

    /// Measure execution time
    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let trace = startTrace(name)
        defer { stopTrace(trace) }
        return try operation()
    }

    func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let trace = startTrace(name)
        defer { stopTrace(trace) }
        return try await operation()
    }
}

// MARK: - Analytics Provider Protocol

protocol AnalyticsProvider {
    func setUserId(_ userId: String)
    func setUserProperty(_ key: String, value: String)
    func clearUserData()
    func trackEvent(_ event: AnalyticsEvent)
    func logError(_ error: Error, additionalInfo: [String: Any])
    func logCrash(_ error: Error, stackTrace: String?)
    func addBreadcrumb(_ breadcrumb: Breadcrumb)
    func startTrace(_ trace: PerformanceTrace)
    func stopTrace(_ trace: PerformanceTrace)
}

// MARK: - Models

struct AnalyticsEvent {
    let name: String
    let category: EventCategory
    let parameters: [String: Any]
    let timestamp: Date

    init(name: String, category: EventCategory, parameters: [String: Any] = [:], timestamp: Date = Date()) {
        self.name = name
        self.category = category
        self.parameters = parameters
        self.timestamp = timestamp
    }

    enum EventCategory {
        case authentication
        case nfc
        case checkin
        case navigation
        case error
        case performance
        case user
    }
}

struct Breadcrumb {
    let message: String
    let category: String
    let level: BreadcrumbLevel
    let timestamp: Date

    init(message: String, category: String, level: BreadcrumbLevel, timestamp: Date = Date()) {
        self.message = message
        self.category = category
        self.level = level
        self.timestamp = timestamp
    }
}

enum BreadcrumbLevel {
    case debug, info, warning, error, critical
}

class PerformanceTrace {
    let name: String
    let startTime: Date
    var endTime: Date?

    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    init(name: String) {
        self.name = name
        self.startTime = Date()
    }

    func stop() {
        endTime = Date()
    }
}

// MARK: - Console Analytics Provider (for debugging)

class ConsoleAnalyticsProvider: AnalyticsProvider {
    func setUserId(_ userId: String) {
        print("📊 [Analytics] Set User ID: \(userId)")
    }

    func setUserProperty(_ key: String, value: String) {
        print("📊 [Analytics] User Property: \(key) = \(value)")
    }

    func clearUserData() {
        print("📊 [Analytics] Cleared user data")
    }

    func trackEvent(_ event: AnalyticsEvent) {
        print("📊 [Analytics] Event: \(event.name)")
        if !event.parameters.isEmpty {
            print("   Parameters: \(event.parameters)")
        }
    }

    func logError(_ error: Error, additionalInfo: [String: Any]) {
        print("❌ [Analytics] Error: \(error.localizedDescription)")
        if !additionalInfo.isEmpty {
            print("   Info: \(additionalInfo)")
        }
    }

    func logCrash(_ error: Error, stackTrace: String?) {
        print("💥 [Analytics] CRASH: \(error.localizedDescription)")
        if let stackTrace = stackTrace {
            print("   Stack: \(stackTrace)")
        }
    }

    func addBreadcrumb(_ breadcrumb: Breadcrumb) {
        let emoji = breadcrumbEmoji(for: breadcrumb.level)
        print("\(emoji) [Breadcrumb] [\(breadcrumb.category)] \(breadcrumb.message)")
    }

    func startTrace(_ trace: PerformanceTrace) {
        print("⏱️ [Performance] Started trace: \(trace.name)")
    }

    func stopTrace(_ trace: PerformanceTrace) {
        if let duration = trace.duration {
            print("⏱️ [Performance] Stopped trace: \(trace.name) (\(String(format: "%.3f", duration))s)")
        }
    }

    private func breadcrumbEmoji(for level: BreadcrumbLevel) -> String {
        switch level {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
}

// MARK: - Predefined Events

extension AnalyticsEvent {
    // Authentication events
    static func signInAttempt() -> AnalyticsEvent {
        AnalyticsEvent(name: "sign_in_attempt", category: .authentication)
    }

    static func signInSuccess() -> AnalyticsEvent {
        AnalyticsEvent(name: "sign_in_success", category: .authentication)
    }

    static func signInFailure(reason: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "sign_in_failure", category: .authentication, parameters: ["reason": reason])
    }

    static func signOut() -> AnalyticsEvent {
        AnalyticsEvent(name: "sign_out", category: .authentication)
    }

    // NFC events
    static func nfcScanStarted() -> AnalyticsEvent {
        AnalyticsEvent(name: "nfc_scan_started", category: .nfc)
    }

    static func nfcScanSuccess(wristbandId: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "nfc_scan_success", category: .nfc, parameters: ["wristband_id": wristbandId])
    }

    static func nfcScanFailure(reason: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "nfc_scan_failure", category: .nfc, parameters: ["reason": reason])
    }

    // Check-in events
    static func checkinAttempt() -> AnalyticsEvent {
        AnalyticsEvent(name: "checkin_attempt", category: .checkin)
    }

    static func checkinSuccess(wristbandId: String, gateId: String?) -> AnalyticsEvent {
        var params: [String: Any] = ["wristband_id": wristbandId]
        if let gateId = gateId {
            params["gate_id"] = gateId
        }
        return AnalyticsEvent(name: "checkin_success", category: .checkin, parameters: params)
    }

    static func checkinFailure(reason: String) -> AnalyticsEvent {
        AnalyticsEvent(name: "checkin_failure", category: .checkin, parameters: ["reason": reason])
    }

    // Error events
    static func appError(error: Error) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "app_error",
            category: .error,
            parameters: [
                "error_type": String(describing: type(of: error)),
                "error_message": error.localizedDescription
            ]
        )
    }
}

// MARK: - Convenience Extensions

extension AnalyticsManager {
    // Quick event tracking
    func trackSignIn() {
        trackEvent(.signInAttempt())
    }

    func trackNFCScan(success: Bool, wristbandId: String? = nil, error: String? = nil) {
        if success, let wristbandId = wristbandId {
            trackEvent(.nfcScanSuccess(wristbandId: wristbandId))
        } else if let error = error {
            trackEvent(.nfcScanFailure(reason: error))
        }
    }

    func trackCheckin(success: Bool, wristbandId: String? = nil, gateId: String? = nil, error: String? = nil) {
        if success, let wristbandId = wristbandId {
            trackEvent(.checkinSuccess(wristbandId: wristbandId, gateId: gateId))
        } else if let error = error {
            trackEvent(.checkinFailure(reason: error))
        }
    }
}
