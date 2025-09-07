import SwiftUI
import Blend

// MARK: - Data Models

struct Photo: Codable, Identifiable {
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Endpoints

struct PhotosEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String = "/photos"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = [URLQueryItem(name: "_limit", value: "10")]
    var contentType: String? = nil
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var port: Int? = nil
    var fragment: String? = nil
}

// MARK: - Service

struct PhotoService: AsyncRequestable {
    typealias ResponseModel = [Photo]

    func getPhotos() async throws -> [Photo] {
        return try await sendRequest(to: PhotosEndpoint())
    }
}

// MARK: - View Models

@MainActor
class PhotoGalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false
    @Published var error: NetworkError?

    private let photoService = PhotoService()
    let imageService = ImageService()

    func loadPhotos() async {
        isLoading = true
        error = nil

        do {
            photos = try await photoService.getPhotos()
        } catch let networkError as NetworkError {
            error = networkError
        } catch {
            // Convert to NetworkError for consistency
            let urlError = URLError(.unknown)
            self.error = .transportError(code: .unknown, underlying: urlError)
        }

        isLoading = false
    }
}

// MARK: - Views

struct PhotoRow: View {
    let photo: Photo
    let imageService: ImageService

    var body: some View {
        HStack {
            Rectangle()
                .frame(width: 60, height: 60)
                .overlay(
                    AsyncNetImageView(
                        url: photo.thumbnailUrl,
                        imageService: imageService
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                )

            VStack(alignment: .leading) {
                Text(photo.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("ID: \(photo.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PhotoGalleryView: View {
    @StateObject private var viewModel = PhotoGalleryViewModel()

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading photos...")
                        .progressViewStyle(.circular)
                } else if let error = viewModel.error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Failed to load photos")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await viewModel.loadPhotos()
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top)
                    }
                    .padding()
                } else {
                    List(viewModel.photos) { photo in
                        PhotoRow(photo: photo, imageService: viewModel.imageService)
                    }
                    .navigationTitle("Photo Gallery")
                }
            }
            .task {
                await viewModel.loadPhotos()
            }
        }
    }
}

// MARK: - App

@main
struct SwiftUIIntegrationApp: App {
    var body: some Scene {
        WindowGroup {
            PhotoGalleryView()
        }
    }
}