import XCTest
@testable import NFCDemo

final class WristbandRepositoryTests: XCTestCase {
    var sut: WristbandRepository!
    var mockNetworkClient: MockNetworkClient!

    override func setUp() {
        super.setUp()
        mockNetworkClient = MockNetworkClient()
        sut = WristbandRepository(networkClient: mockNetworkClient)
    }

    override func tearDown() {
        sut = nil
        mockNetworkClient = nil
        super.tearDown()
    }

    func testFetchWristbandsSuccess() async throws {
        // Given
        let eventId = "test-event-id"
        let mockWristbands = [
            createMockWristband(id: "1", nfcId: "NFC001"),
            createMockWristband(id: "2", nfcId: "NFC002")
        ]

        mockNetworkClient.mockResponse = mockWristbands

        // When
        let wristbands = try await sut.fetchWristbands(for: eventId)

        // Then
        XCTAssertEqual(wristbands.count, 2)
        XCTAssertEqual(wristbands[0].nfcId, "NFC001")
        XCTAssertEqual(wristbands[1].nfcId, "NFC002")
    }

    func testFetchWristbandByNFCIdFound() async throws {
        // Given
        let mockWristband = createMockWristband(id: "1", nfcId: "NFC001")
        mockNetworkClient.mockResponse = [mockWristband]

        // When
        let wristband = try await sut.fetchWristband(by: "NFC001", eventId: "event-1")

        // Then
        XCTAssertNotNil(wristband)
        XCTAssertEqual(wristband?.nfcId, "NFC001")
    }

    func testFetchWristbandByNFCIdNotFound() async throws {
        // Given
        mockNetworkClient.mockResponse = [Wristband]()

        // When
        let wristband = try await sut.fetchWristband(by: "NONEXISTENT", eventId: "event-1")

        // Then
        XCTAssertNil(wristband)
    }

    func testCreateWristband() async throws {
        // Given
        let newWristband = createMockWristband(id: "new-1", nfcId: "NFC999")
        mockNetworkClient.mockResponse = [newWristband]

        // When
        let created = try await sut.createWristband(newWristband)

        // Then
        XCTAssertEqual(created.id, "new-1")
        XCTAssertEqual(created.nfcId, "NFC999")
    }

    // Helper
    private func createMockWristband(id: String, nfcId: String) -> Wristband {
        Wristband(
            id: id,
            eventId: "event-1",
            nfcId: nfcId,
            category: WristbandCategory(name: "General"),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

final class CheckinRepositoryTests: XCTestCase {
    var sut: CheckinRepository!
    var mockNetworkClient: MockNetworkClient!

    override func setUp() {
        super.setUp()
        mockNetworkClient = MockNetworkClient()
        sut = CheckinRepository(networkClient: mockNetworkClient)
    }

    func testRecordCheckinSuccess() async throws {
        // Given
        let mockLog = createMockCheckinLog()
        mockNetworkClient.mockResponse = [mockLog]

        // When
        let log = try await sut.recordCheckin(
            wristbandId: "wristband-1",
            eventId: "event-1",
            staffId: "staff-1",
            location: "Gate A",
            notes: "Test checkin",
            gateId: "gate-1",
            appLat: 40.7128,
            appLon: -74.0060,
            appAccuracy: 5.0
        )

        // Then
        XCTAssertNotNil(log)
        XCTAssertEqual(log.wristbandId, "wristband-1")
    }

    func testRecordCheckinWithInvalidWristbandId() async {
        // When / Then
        await XCTAssertThrowsError(
            try await sut.recordCheckin(
                wristbandId: "",  // Empty ID
                eventId: "event-1",
                staffId: nil,
                location: nil,
                notes: nil,
                gateId: nil,
                appLat: nil,
                appLon: nil,
                appAccuracy: nil
            )
        )
    }

    func testFetchCheckinLogs() async throws {
        // Given
        let mockLogs = [
            createMockCheckinLog(id: "1"),
            createMockCheckinLog(id: "2")
        ]
        mockNetworkClient.mockResponse = mockLogs

        // When
        let logs = try await sut.fetchCheckinLogs(for: "event-1", limit: 100)

        // Then
        XCTAssertEqual(logs.count, 2)
    }

    private func createMockCheckinLog(id: String = "log-1") -> CheckinLog {
        CheckinLog(
            id: id,
            eventId: "event-1",
            wristbandId: "wristband-1",
            staffId: "staff-1",
            timestamp: Date(),
            location: "Gate A",
            notes: nil,
            gateId: "gate-1",
            scannerId: nil,
            appLat: 40.7128,
            appLon: -74.0060,
            appAccuracy: 5.0,
            bleSeen: nil,
            wifiSSIDs: nil,
            probationTagged: false
        )
    }
}

// MARK: - Mock Network Client

class MockNetworkClient: NetworkClient {
    var mockResponse: Any?
    var mockError: Error?
    var requestCount = 0

    override func execute<T>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        headers: [String : String]?,
        requiresAuth: Bool,
        responseType: T.Type
    ) async throws -> T where T : Decodable {
        requestCount += 1

        if let error = mockError {
            throw error
        }

        if let response = mockResponse as? T {
            return response
        }

        throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No mock response set"])
    }
}

// MARK: - XCTestCase Extension for Async Errors

extension XCTestCase {
    func XCTAssertThrowsError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
