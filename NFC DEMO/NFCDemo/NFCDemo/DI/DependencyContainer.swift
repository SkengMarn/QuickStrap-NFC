import Foundation
import SwiftUI

/// Dependency Injection Container
/// Manages creation and lifecycle of app dependencies
class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    private let logger = AppLogger.shared

    // MARK: - Configuration & Infrastructure

    lazy var configuration: AppConfiguration = {
        logger.info("Initializing AppConfiguration", category: "DI")
        return AppConfiguration.shared
    }()

    lazy var appLogger: AppLogger = {
        return AppLogger.shared
    }()

    lazy var hapticManager: HapticManager = {
        logger.info("Initializing HapticManager", category: "DI")
        return HapticManager.shared
    }()

    lazy var biometricAuthManager: BiometricAuthManager = {
        logger.info("Initializing BiometricAuthManager", category: "DI")
        return BiometricAuthManager.shared
    }()

    // MARK: - Network Layer

    lazy var networkClient: NetworkClient = {
        logger.info("Initializing NetworkClient", category: "DI")
        return NetworkClient.shared
    }()

    // MARK: - Repositories

    lazy var authRepository: AuthRepository = {
        logger.info("Initializing AuthRepository", category: "DI")
        return AuthRepository(networkClient: networkClient)
    }()

    lazy var eventRepository: EventRepository = {
        logger.info("Initializing EventRepository", category: "DI")
        return EventRepository(networkClient: networkClient)
    }()

    lazy var wristbandRepository: WristbandRepository = {
        logger.info("Initializing WristbandRepository", category: "DI")
        return WristbandRepository(networkClient: networkClient)
    }()

    lazy var checkinRepository: CheckinRepository = {
        logger.info("Initializing CheckinRepository", category: "DI")
        return CheckinRepository(networkClient: networkClient)
    }()

    // MARK: - Services

    @Published private(set) var authService: AuthService!
    @Published private(set) var eventService: EventService!

    private init() {
        logger.info("DependencyContainer initialized", category: "DI")
        setupServices()
    }

    private func setupServices() {
        // Initialize services with repositories
        authService = AuthService.shared
        eventService = EventService.shared

        // Configure network client token provider
        authService.configureNetworkClient()
    }

    // MARK: - Factory Methods

    /// Create a new instance of DatabaseScannerViewModel
    @MainActor
    func makeDatabaseScannerViewModel(event: Event) -> DatabaseScannerViewModel {
        logger.debug("Creating DatabaseScannerViewModel", category: "DI")
        return DatabaseScannerViewModel()
    }

    /// Create a new instance of GatesViewModel
    @MainActor
    func makeGatesViewModel(event: Event) -> GatesViewModel {
        logger.debug("Creating GatesViewModel", category: "DI")
        return GatesViewModel()
    }

    // MARK: - Testing Support

    #if DEBUG
    /// Create a mock container for testing
    static func mock() -> DependencyContainer {
        let container = DependencyContainer()
        // In tests, you can replace services with mocks
        return container
    }

    /// Reset singleton (for testing only)
    static func reset() {
        // Reset shared instances if needed for testing
    }
    #endif
}

// MARK: - Environment Key for SwiftUI

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// Inject dependency container into environment
    func withDependencies(_ container: DependencyContainer = .shared) -> some View {
        environment(\.dependencies, container)
            .environmentObject(container.authService)
            .environmentObject(container.eventService)
    }
}

// MARK: - Property Wrapper for Dependency Injection

@propertyWrapper
struct Injected<T> {
    private let keyPath: KeyPath<DependencyContainer, T>

    var wrappedValue: T {
        DependencyContainer.shared[keyPath: keyPath]
    }

    init(_ keyPath: KeyPath<DependencyContainer, T>) {
        self.keyPath = keyPath
    }
}

// MARK: - Usage Examples in Comments

/*
 Usage Example 1: In Views

 struct MyView: View {
     @EnvironmentObject var authService: AuthService
     @EnvironmentObject var eventService: EventService

     // Or use @Injected for specific dependencies
     @Injected(\.hapticManager) var haptics

     var body: some View {
         Text("Hello")
             .onTapGesture {
                 haptics.buttonTap()
             }
     }
 }

 Usage Example 2: In App

 @main
 struct NFCDemoApp: App {
     let container = DependencyContainer.shared

     var body: some Scene {
         WindowGroup {
             ContentView()
                 .withDependencies(container)
         }
     }
 }

 Usage Example 3: In ViewModels

 class MyViewModel: ObservableObject {
     @Injected(\.authRepository) var authRepo
     @Injected(\.networkClient) var network

     func doSomething() {
         // Use injected dependencies
     }
 }

 Usage Example 4: For Testing

 class MyViewModelTests: XCTestCase {
     var sut: MyViewModel!
     var mockContainer: DependencyContainer!

     override func setUp() {
         mockContainer = DependencyContainer.mock()
         // Replace services with mocks
         sut = MyViewModel()
     }
 }
 */
