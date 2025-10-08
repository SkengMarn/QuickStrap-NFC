import Foundation

/// Protocol for network requests
protocol NetworkRequest {
    associatedtype Response: Decodable
    var endpoint: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
    var requiresAuth: Bool { get }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Centralized network client with proper error handling and logging
class NetworkClient: NSObject {
    static let shared = NetworkClient()

    private let session: URLSession
    private let config: AppConfiguration
    private let logger = AppLogger.shared
    private let certificatePinner = CertificatePinner.shared

    // For testing/mocking
    var tokenProvider: (() -> String?)?

    private override init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.config = AppConfiguration.shared

        // Create session with self as delegate for certificate pinning
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)

        super.init()

        // Recreate session with proper delegate
        let delegatedSession = URLSession(configuration: configuration, delegate: certificatePinner, delegateQueue: nil)
        // Note: In production, you'd use this delegated session
        // For now, we keep the basic session to avoid breaking changes during migration
    }

    // MARK: - Generic Request Method

    func execute<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true,
        responseType: T.Type
    ) async throws -> T {
        return try await logger.measureAsync("API Request: \(method.rawValue) \(endpoint)", category: "Network") {
            // Build URL
            guard let url = buildURL(endpoint: endpoint) else {
                throw AppError.invalidConfiguration("Invalid URL for endpoint: \(endpoint)")
            }

            // Build request
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.httpBody = body

            // Add headers
            request = addHeaders(to: request, customHeaders: headers, requiresAuth: requiresAuth)

            // Log request
            logRequest(request)

            // Execute request
            let (data, response) = try await session.data(for: request)

            // Handle response
            return try handleResponse(data: data, response: response, responseType: responseType)
        }
    }

    // MARK: - Request Building

    private func buildURL(endpoint: String) -> URL? {
        let baseURL = config.supabaseURL

        // Handle full URLs vs relative endpoints
        if endpoint.starts(with: "http") {
            return URL(string: endpoint)
        }

        let fullURL = "\(baseURL)/\(endpoint)"
        return URL(string: fullURL)
    }

    private func addHeaders(to request: URLRequest, customHeaders: [String: String]?, requiresAuth: Bool) -> URLRequest {
        var request = request

        // Base headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // API Key (always needed for Supabase)
        let apiKey = config.supabaseAnonKey
        request.setValue(apiKey, forHTTPHeaderField: "apikey")

        // Authorization
        if requiresAuth {
            if let token = tokenProvider?() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }

        // Custom headers
        customHeaders?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    // MARK: - Response Handling

    private func handleResponse<T: Decodable>(data: Data, response: URLResponse, responseType: T.Type) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError(.invalidResponse)
        }

        logResponse(httpResponse, data: data)

        // Handle HTTP errors
        guard 200...299 ~= httpResponse.statusCode else {
            throw handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        // Handle empty responses
        if data.isEmpty && T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        // Decode response
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Try multiple formats
                let formatters: [ISO8601DateFormatter] = [
                    {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        return formatter
                    }(),
                    ISO8601DateFormatter(),
                ]

                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }

                // Fallback to standard DateFormatter
                let fallbackFormatter = DateFormatter()
                fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)

                if let date = fallbackFormatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot decode date: \(dateString)"
                )
            }

            return try decoder.decode(responseType, from: data)
        } catch let decodingError as DecodingError {
            logger.error("Decoding error: \(decodingError)", category: "Network")

            if let dataString = String(data: data, encoding: .utf8) {
                logger.debug("Response data: \(dataString)", category: "Network")
            }

            throw AppError.decodingError(decodingError.localizedDescription)
        }
    }

    private func handleHTTPError(statusCode: Int, data: Data) -> AppError {
        // Try to parse error message from response
        var errorMessage: String?

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            errorMessage = json["message"] as? String ?? json["error"] as? String
        }

        // Map to appropriate error
        switch statusCode {
        case 400:
            return .apiError(.custom(400, errorMessage ?? "Bad request"))
        case 401:
            return .authenticationFailed(errorMessage ?? "Unauthorized")
        case 403:
            return .apiError(.forbidden)
        case 404:
            return .apiError(.notFound)
        case 409:
            return .apiError(.conflict)
        case 429:
            return .apiError(.rateLimited)
        case 500...599:
            return .networkError(.serverError(statusCode, errorMessage))
        default:
            return .apiError(.custom(statusCode, errorMessage ?? "Unknown error"))
        }
    }

    // MARK: - Logging

    private func logRequest(_ request: URLRequest) {
        logger.debug("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")", category: "Network")

        #if DEBUG
        if let headers = request.allHTTPHeaderFields {
            let sanitizedHeaders = headers.mapValues { value in
                // Sanitize sensitive headers
                if value.count > 20 {
                    return "\(value.prefix(10))...\(value.suffix(10))"
                }
                return value
            }
            logger.debug("Headers: \(sanitizedHeaders)", category: "Network")
        }

        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            logger.debug("Body: \(bodyString)", category: "Network")
        }
        #endif
    }

    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        let statusEmoji = (200...299).contains(response.statusCode) ? "✅" : "❌"
        logger.debug("\(statusEmoji) ← \(response.statusCode) (\(data.count) bytes)", category: "Network")

        #if DEBUG
        if !(200...299).contains(response.statusCode),
           let responseString = String(data: data, encoding: .utf8) {
            logger.debug("Error response: \(responseString)", category: "Network")
        }
        #endif
    }
}

// MARK: - Empty Response Type
struct EmptyResponse: Codable {
    init() {}
}

// MARK: - Convenience Extensions
extension NetworkClient {
    func get<T: Decodable>(
        endpoint: String,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true,
        responseType: T.Type
    ) async throws -> T {
        try await execute(
            endpoint: endpoint,
            method: .get,
            headers: headers,
            requiresAuth: requiresAuth,
            responseType: responseType
        )
    }

    func post<T: Decodable>(
        endpoint: String,
        body: Data?,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true,
        responseType: T.Type
    ) async throws -> T {
        try await execute(
            endpoint: endpoint,
            method: .post,
            body: body,
            headers: headers,
            requiresAuth: requiresAuth,
            responseType: responseType
        )
    }

    func patch<T: Decodable>(
        endpoint: String,
        body: Data?,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true,
        responseType: T.Type
    ) async throws -> T {
        try await execute(
            endpoint: endpoint,
            method: .patch,
            body: body,
            headers: headers,
            requiresAuth: requiresAuth,
            responseType: responseType
        )
    }

    func delete(
        endpoint: String,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true
    ) async throws {
        let _: EmptyResponse = try await execute(
            endpoint: endpoint,
            method: .delete,
            headers: headers,
            requiresAuth: requiresAuth,
            responseType: EmptyResponse.self
        )
    }
}
