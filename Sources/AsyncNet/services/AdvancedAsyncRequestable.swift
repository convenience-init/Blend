import Foundation

/// Advanced networking protocol for services requiring multiple response types and complex service patterns.
///
/// `AdvancedAsyncRequestable` extends the basic `AsyncRequestable` protocol to support services that need
/// both primary and secondary response types. This enables powerful patterns like master-detail views,
/// CRUD operations with different response types, generic service composition, and type-safe service hierarchies.
///
/// ## When to Use AdvancedAsyncRequestable
///
/// Choose `AdvancedAsyncRequestable` over `AsyncRequestable` when your service needs:
///
/// ### 1. Master-Detail Patterns
/// ```swift
/// class UserService: AdvancedAsyncRequestable {
///     typealias ResponseModel = [UserSummary]     // List view
///     typealias SecondaryResponseModel = UserDetails // Detail view
///
///     func getUsers() async throws -> [UserSummary] {
///         return try await fetchList(from: UsersEndpoint())
///     }
///
///     func getUserDetails(id: String) async throws -> UserDetails {
///         return try await fetchDetails(from: UserDetailsEndpoint(id: id))
///     }
/// }
/// ```
///
/// ### 2. CRUD Operations with Different Response Types
/// ```swift
/// class ProductService: AdvancedAsyncRequestable {
///     typealias ResponseModel = [ProductSummary]  // List/Create responses
///     typealias SecondaryResponseModel = ProductDetails // Detail/Update responses
///
///     func getProducts() async throws -> [ProductSummary] {
///         return try await fetchList(from: ProductsEndpoint())
///     }
///
///     func getProduct(id: String) async throws -> ProductDetails {
///         return try await fetchDetails(from: ProductDetailsEndpoint(id: id))
///     }
///
///     func createProduct(_ input: ProductInput) async throws -> ProductDetails {
///         return try await sendRequest(to: CreateProductEndpoint(input: input))
///     }
/// }
/// ```
///
/// ### 3. Multi-Response Service Pattern
/// ```swift
/// protocol MultiResponseService: AdvancedAsyncRequestable {
///     // Inherits ResponseModel and SecondaryResponseModel from AdvancedAsyncRequestable
///
///     func getPrimaryData() async throws -> ResponseModel
///     func getSecondaryData() async throws -> SecondaryResponseModel
/// }
///
/// class UserService: MultiResponseService {
///     typealias ResponseModel = [UserSummary]
///     typealias SecondaryResponseModel = UserDetails
///
///     func getPrimaryData() async throws -> [UserSummary] {
///         return try await fetchList(from: UsersEndpoint())
///     }
///
///     func getSecondaryData() async throws -> UserDetails {
///         return try await fetchDetails(from: UserDetailsEndpoint())
///     }
/// }
/// ```
///
/// ### 4. Generic Service Composition
/// ```swift
/// class GenericCrudService<T: AdvancedAsyncRequestable>: AsyncRequestable {
///     typealias ResponseModel = T.ResponseModel
///
///     func listItems() async throws -> T.ResponseModel {
///         // Generic implementation for any service's list operation
///     }
///
///     func getItemDetails(id: String) async throws -> T.SecondaryResponseModel {
///         // Generic implementation for any service's detail operation
///     }
/// }
/// ```
///
/// ### 5. Type-Safe Service Hierarchies
/// ```swift
/// protocol EcommerceService: AdvancedAsyncRequestable
/// where ResponseModel: Sequence, ResponseModel.Element == ProductSummary {
///     // All ecommerce services must have ProductSummary as their list type
/// }
///
/// class ProductService: EcommerceService {
///     typealias ResponseModel = [ProductSummary]
///     typealias SecondaryResponseModel = ProductDetails
///     // Implementation...
/// }
/// ```
///
/// ## Protocol Relationship
///
/// ```
/// AsyncRequestable (Basic)
///   ↳ AdvancedAsyncRequestable (Enhanced)
/// ```
///
/// - **AsyncRequestable**: Use for simple services with single response types
/// - **AdvancedAsyncRequestable**: Use for complex services requiring multiple response types
///
/// ## Associated Types
///
/// - `ResponseModel`: The primary response type, typically used for list/collection operations
/// - `SecondaryResponseModel`: The secondary response type, typically used for detail/single-item operations
///
/// ## Type Constraints
///
/// Convention: `ResponseModel` is often a collection type (e.g., `[Summary]`), but this protocol
/// does not require it. `SecondaryResponseModel` can be any `Decodable` type.
///
/// ## Convenience Methods
///
/// This protocol provides convenience methods `fetchList()` and `fetchDetails()` that automatically
/// use the correct associated types, reducing boilerplate and potential type errors.
///
/// ## Migration from AsyncRequestable
///
/// To migrate from `AsyncRequestable` to `AdvancedAsyncRequestable`:
/// 1. Change the protocol conformance: `AsyncRequestable` → `AdvancedAsyncRequestable`
/// 2. Add the `SecondaryResponseModel` associated type
/// 3. Update method implementations to use `fetchList()` and `fetchDetails()` where appropriate
///
/// ## Thread Safety
///
/// Like `AsyncRequestable`, this protocol is designed for Swift 6 concurrency and supports
/// actor-isolated implementations for thread safety.
///
/// ## Performance Considerations
///
/// The dual-type pattern adds minimal overhead while providing significant type safety benefits.
/// The convenience methods are inlined for optimal performance.
public protocol AdvancedAsyncRequestable: AsyncRequestable {
	/// Associated type for the secondary response model type used by this service.
	///
	/// This represents the "detail" or "single-item" response type, complementing the
	/// primary `ResponseModel` which typically represents list/collection responses.
	///
	/// ## Usage Examples
	///
	/// **Simple Detail Type:**
	/// ```swift
	/// typealias SecondaryResponseModel = UserDetails
	/// ```
	///
	/// **Complex Detail Type:**
	/// ```swift
	/// typealias SecondaryResponseModel = APIResponse<UserProfile>
	/// ```
	///
	/// **Generic Detail Type:**
	/// ```swift
	/// typealias SecondaryResponseModel = T.Details where T: DetailResponseProtocol
	/// ```
	associatedtype SecondaryResponseModel: Decodable
}

/// Convenience methods for AdvancedAsyncRequestable services.
///
/// These methods provide type-safe operations that automatically use the correct
/// associated types, reducing boilerplate and potential errors.
///
/// Note: Explicit 'public' modifiers are used for library clarity and maintainability,
/// even though they are technically redundant in public extensions. This practice
/// makes the API surface explicit and helps with future refactoring.
public extension AdvancedAsyncRequestable {
	/// Fetches a list of items using the primary ResponseModel type.
	///
	/// This method automatically uses the `ResponseModel` associated type,
	/// ensuring type safety for list/collection operations.
	///
	/// - Parameter endpoint: The endpoint to fetch the list from
	/// - Returns: A list of items of type `ResponseModel`
	/// - Throws: `NetworkError` if the request fails
	///
	/// ## Example
	/// ```swift
	/// let users: [UserSummary] = try await fetchList(from: UsersEndpoint())
	/// ```
	@discardableResult
	public func fetchList(from endpoint: Endpoint) async throws -> ResponseModel {
		return try await sendRequest(to: endpoint)
	}

	/// Fetches a single item's details using the SecondaryResponseModel type.
	///
	/// This method automatically uses the `SecondaryResponseModel` associated type,
	/// ensuring type safety for detail/single-item operations.
	///
	/// - Parameter endpoint: The endpoint to fetch the details from
	/// - Returns: A single item of type `SecondaryResponseModel`
	/// - Throws: `NetworkError` if the request fails
	///
	/// ## Example
	/// ```swift
	/// let userDetails: UserDetails = try await fetchDetails(from: UserDetailsEndpoint(id: "123"))
	/// ```
	@discardableResult
	public func fetchDetails(from endpoint: Endpoint) async throws -> SecondaryResponseModel {
		return try await sendRequest(to: endpoint)
	}
}