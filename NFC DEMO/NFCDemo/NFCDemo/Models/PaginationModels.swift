import Foundation

/// Generic paginated response wrapper
struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let pagination: PaginationMetadata

    var items: [T] { data }
    var hasMore: Bool { pagination.hasMore }
    var currentPage: Int { pagination.currentPage }
    var totalPages: Int { pagination.totalPages }
}

/// Pagination metadata
struct PaginationMetadata: Codable {
    let currentPage: Int
    let pageSize: Int
    let totalCount: Int
    let totalPages: Int

    var hasMore: Bool {
        currentPage < totalPages - 1
    }

    var hasPrevious: Bool {
        currentPage > 0
    }

    init(currentPage: Int, pageSize: Int, totalCount: Int) {
        self.currentPage = currentPage
        self.pageSize = pageSize
        self.totalCount = totalCount
        self.totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
    }
}

/// Pagination request parameters
struct PaginationParams {
    let page: Int
    let pageSize: Int
    let offset: Int

    init(page: Int = 0, pageSize: Int = 50) {
        self.page = page
        self.pageSize = pageSize
        self.offset = page * pageSize
    }

    /// Get query parameters for Supabase
    var supabaseParams: String {
        "limit=\(pageSize)&offset=\(offset)"
    }
}

/// Pagination state manager for SwiftUI
@MainActor
class PaginationState<T: Codable>: ObservableObject {
    @Published var items: [T] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: Error?
    @Published var hasMore = true

    private(set) var currentPage = 0
    private(set) var pageSize: Int
    private(set) var totalCount = 0

    init(pageSize: Int = 50) {
        self.pageSize = pageSize
    }

    /// Load first page
    func loadInitial(loader: @escaping @Sendable (PaginationParams) async throws -> PaginatedResponse<T>) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentPage = 0
        items = []

        do {
            let params = PaginationParams(page: 0, pageSize: pageSize)
            let response = try await loader(params)

            items = response.data
            totalCount = response.pagination.totalCount
            hasMore = response.hasMore
            currentPage = 0
        } catch {
            self.error = error
            AppLogger.shared.error("Failed to load initial page: \(error)", category: "Pagination")
        }

        isLoading = false
    }

    /// Load next page
    func loadMore(loader: @escaping @Sendable (PaginationParams) async throws -> PaginatedResponse<T>) async {
        guard !isLoadingMore && hasMore else { return }

        isLoadingMore = true

        do {
            let nextPage = currentPage + 1
            let params = PaginationParams(page: nextPage, pageSize: pageSize)
            let response = try await loader(params)

            items.append(contentsOf: response.data)
            totalCount = response.pagination.totalCount
            hasMore = response.hasMore
            currentPage = nextPage
        } catch {
            self.error = error
            AppLogger.shared.error("Failed to load more: \(error)", category: "Pagination")
        }

        isLoadingMore = false
    }

    /// Refresh (reload first page)
    func refresh(loader: @escaping @Sendable (PaginationParams) async throws -> PaginatedResponse<T>) async {
        await loadInitial(loader: loader)
    }

    /// Reset state
    func reset() {
        items = []
        currentPage = 0
        totalCount = 0
        hasMore = true
        error = nil
        isLoading = false
        isLoadingMore = false
    }
}

// MARK: - Repository Extension for Pagination
// Note: These extensions will be moved to their respective repository files
// to access private properties properly

// MARK: - SwiftUI View Helpers

#if canImport(SwiftUI)
import SwiftUI

/// View modifier for pagination loading indicator
struct PaginationLoadingModifier<T: Codable>: ViewModifier {
    @ObservedObject var state: PaginationState<T>

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if state.isLoadingMore {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
    }
}

extension View {
    func paginationLoading<T: Codable>(_ state: PaginationState<T>) -> some View {
        modifier(PaginationLoadingModifier(state: state))
    }
}

/// Pagination trigger view (place at bottom of list)
struct PaginationTrigger: View {
    let onAppear: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear(perform: onAppear)
    }
}

#endif

// MARK: - Usage Example in Comments

/*
 Usage Example in ViewModel:

 class WristbandsViewModel: ObservableObject {
     @Published var paginationState = PaginationState<Wristband>(pageSize: 50)
     private let repository: WristbandRepository
     private let eventId: String

     init(eventId: String, repository: WristbandRepository) {
         self.eventId = eventId
         self.repository = repository
     }

     func loadWristbands() async {
         await paginationState.loadInitial { params in
             try await repository.fetchWristbandsPaginated(eventId: eventId, params: params)
         }
     }

     func loadMore() async {
         await paginationState.loadMore { params in
             try await repository.fetchWristbandsPaginated(eventId: eventId, params: params)
         }
     }
 }

 Usage Example in View:

 struct WristbandsListView: View {
     @StateObject var viewModel: WristbandsViewModel

     var body: some View {
         List {
             ForEach(viewModel.paginationState.items) { wristband in
                 WristbandRow(wristband: wristband)
             }

             if viewModel.paginationState.hasMore {
                 PaginationTrigger {
                     Task {
                         await viewModel.loadMore()
                     }
                 }
             }
         }
         .paginationLoading(viewModel.paginationState)
         .task {
             await viewModel.loadWristbands()
         }
         .refreshable {
             await viewModel.paginationState.refresh { params in
                 try await viewModel.repository.fetchWristbandsPaginated(
                     eventId: viewModel.eventId,
                     params: params
                 )
             }
         }
     }
 }
 */
