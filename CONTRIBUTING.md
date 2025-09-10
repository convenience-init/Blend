# Contributing to Blend

Thank you for your interest in contributing to Blend! This document provides guidelines and information for contributors.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Reporting Issues](#reporting-issues)

## 🤝 Code of Conduct

This project follows a code of conduct to ensure a welcoming environment for all contributors. By participating, you agree to:

- Be respectful and inclusive
- Focus on constructive feedback
- Accept responsibility for mistakes
- Show empathy towards other contributors
- Help create a positive community

## 🚀 Getting Started

### Prerequisites

- **Swift**: 6.0 or later
- **Xcode**: 16.0 or later
- **Platforms**: iOS 18.0+ or macOS 15.0+
- **Git**: Latest version

### Quick Setup

1. **Fork the repository**
   ```bash
   git clone https://github.com/your-username/Blend.git
   cd Blend
   ```

2. **Set up development environment**
   ```bash
   # Install dependencies (if any)
   swift package resolve

   # Run tests to verify setup
   swift test
   ```

3. **Create a branch for your changes**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🛠️ Development Setup

### Environment Configuration

Blend requires specific Swift 6 features and platform versions:

```swift
// Package.swift configuration
let package = Package(
    name: "Blend",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    swiftLanguageModes: [.v6]  // Required for strict concurrency
)
```

### IDE Setup

#### Xcode Configuration
1. Open `Blend.xcodeproj` or use Swift Package Manager
2. Set Swift Language Version to 6.0
3. Enable Strict Concurrency Checking
4. Set deployment targets:
   - iOS: 18.0
   - macOS: 15.0

#### VS Code Configuration (Alternative)
```json
{
    "swift.languageVersion": "6.0",
    "swift.buildArguments": [
        "-Xswiftc", "-strict-concurrency=complete"
    ]
}
```

## 📁 Project Structure

```
Blend/
├── Sources/Blend/
│   ├── Core/
│   │   ├── Errors/           # NetworkError and error handling
│   │   ├── Networking/       # Core networking infrastructure
│   │   ├── Protocols/        # AsyncRequestable, AdvancedAsyncRequestable
│   │   └── Utilities/        # Helper utilities and extensions
│   ├── Image/
│   │   ├── Cache/           # Image caching implementation
│   │   ├── Operations/      # Image processing and MIME detection
│   │   ├── Platform/        # Platform-specific extensions
│   │   └── Service/         # ImageService actor
│   ├── Infrastructure/
│   │   ├── Cache/           # Network cache implementation
│   │   ├── Configuration/   # Retry policies and config
│   │   └── Utilities/       # Request interceptors
│   └── UI/
│       └── SwiftUI/         # SwiftUI integration components
├── Tests/
│   └── BlendTests/          # Comprehensive test suite
├── Examples/                # Example projects
├── docs/                    # Documentation
└── scripts/                 # Build and utility scripts
```

## 🔄 Development Workflow

### 1. Choose an Issue
- Check [GitHub Issues](https://github.com/convenience-init/Blend/issues) for open tasks
- Look for issues labeled `good first issue` or `help wanted`
- Comment on the issue to indicate you're working on it

### 2. Create a Branch
```bash
# For features
git checkout -b feature/descriptive-name

# For bug fixes
git checkout -b fix/issue-number-description

# For documentation
git checkout -b docs/update-section
```

### 3. Make Changes
- Follow the coding standards below
- Write tests for new functionality
- Update documentation as needed
- Ensure all tests pass

### 4. Test Your Changes
```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter ImageServiceTests

# Run with code coverage
swift test --enable-code-coverage
```

### 5. Commit Your Changes
```bash
# Stage your changes
git add .

# Commit with descriptive message
git commit -m "feat: add new image upload functionality

- Add multipart upload support
- Add progress tracking
- Add error handling for upload failures
- Add comprehensive tests

Closes #123"
```

## 💻 Coding Standards

### Swift Style Guide

Blend follows the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) and [Swift.org style](https://swift.org/documentation/api-design-guidelines/).

#### Naming Conventions
```swift
// Protocols
protocol AsyncRequestable { }

// Classes and Structs
class ImageService { }
struct UploadConfiguration { }

// Enums
enum RequestMethod {
    case get, post, put, delete
}

// Functions and Methods
func fetchImageData(from urlString: String) async throws -> Data
func uploadImage(_ imageData: Data, to url: URL) async throws -> Data

// Properties
let imageService: ImageService
var isLoading: Bool
```

#### Documentation Comments
```swift
/// Fetches image data from the specified URL string.
///
/// This method handles caching, retry logic, and error conversion automatically.
/// The image data is cached for future requests to improve performance.
///
/// - Parameter urlString: The URL string of the image to fetch
/// - Returns: The raw image data
/// - Throws: `NetworkError` if the request fails
/// - Important: This method is actor-isolated and must be called from the same actor
func fetchImageData(from urlString: String) async throws -> Data
```

### Swift 6 Concurrency

#### Actor Isolation
```swift
// Correct: Actor-isolated state
actor ImageService {
    private var cache: [String: PlatformImage] = [:]

    func cachedImage(forKey key: String) -> PlatformImage? {
        cache[key]
    }
}

// Incorrect: Shared mutable state without isolation
class BadImageService {
    private var cache: [String: PlatformImage] = [:] // ❌ Race condition risk
}
```

#### Sendable Conformance
```swift
// Correct: Sendable data types
struct UploadConfiguration: Sendable {
    let fieldName: String
    let fileName: String
    let compressionQuality: CGFloat
}

// Correct: Actor-isolated reference types
actor ImageService: Sendable { }
```

#### MainActor for UI
```swift
@MainActor
class AsyncImageModel: ObservableObject {
    @Published var loadedImage: PlatformImage?
    @Published var isLoading = false

    // All UI updates happen on main thread
    func loadImage(from url: String?) async {
        // Implementation
    }
}
```

### Error Handling

#### NetworkError Usage
```swift
// Correct: Specific error cases
do {
    let data = try await imageService.fetchImageData(from: url)
} catch let error as NetworkError {
    switch error {
    case .networkUnavailable:
        // Handle no connectivity
    case .httpError(let statusCode, _):
        // Handle HTTP errors
    case .decodingError:
        // Handle JSON parsing errors
    default:
        // Handle other errors
    }
}
```

#### Custom Errors
```swift
enum ImageProcessingError: Error {
    case invalidData
    case unsupportedFormat
    case compressionFailed
}
```

## 🧪 Testing

### Test Structure
```swift
class ImageServiceTests: XCTestCase {
    var imageService: ImageService!
    var mockSession: URLSession!

    override func setUp() async throws {
        imageService = ImageService()
        mockSession = createMockSession()
    }

    override func tearDown() async throws {
        imageService = nil
        mockSession = nil
    }

    func testFetchImageDataSuccess() async throws {
        // Given
        let expectedData = try Data(contentsOf: testImageURL)

        // When
        let result = try await imageService.fetchImageData(from: "https://example.com/image.jpg")

        // Then
        XCTAssertEqual(result, expectedData)
    }
}
```

### Test Coverage Goals
- **Unit Tests**: 90%+ coverage for all new code
- **Integration Tests**: End-to-end workflows
- **Platform Tests**: iOS and macOS compatibility
- **Error Tests**: All error paths covered

### Running Tests
```bash
# All tests
swift test

# Specific test class
swift test --filter ImageServiceTests

# With verbose output
swift test -v

# Generate coverage report
swift test --enable-code-coverage
```

## 📚 Documentation

### Code Documentation
- All public APIs must have documentation comments
- Include usage examples in doc comments
- Document parameters, return values, and thrown errors
- Mark important notes with `- Important:` or `- Note:`

### README Updates
- Update README.md for new features
- Add examples for new functionality
- Update installation instructions if needed
- Update platform requirements

### API Documentation
- Update `docs/API_REFERENCE.md` for new APIs
- Add examples to `Examples/` directory
- Update CHANGELOG.md for changes

## 📤 Submitting Changes

### Pull Request Process

1. **Ensure tests pass**
   ```bash
   swift test
   ```

2. **Update documentation**
   - Code comments
   - README examples
   - API reference

3. **Create pull request**
   - Use descriptive title
   - Reference issue number
   - Provide detailed description
   - Include screenshots for UI changes

4. **Code review**
   - Address review comments
   - Make requested changes
   - Ensure CI passes

### Commit Message Format

```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Testing
- `chore`: Maintenance

**Examples:**
```
feat: add image upload with progress tracking

- Add UploadProgress struct
- Add progress callback to ImageService
- Update SwiftUI components for progress display

Closes #123
```

```
fix: resolve memory leak in image cache

- Fix strong reference cycle in LRU cache
- Add proper cleanup in deinit
- Add test for memory management

Fixes #456
```

## 🐛 Reporting Issues

### Bug Reports

**Good bug report** includes:
- Clear title describing the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (Swift version, platform, Xcode version)
- Code snippets or example project
- Screenshots for UI issues

**Template:**
```markdown
## Bug Report

**Description:**
Brief description of the bug

**Steps to Reproduce:**
1. Step 1
2. Step 2
3. Step 3

**Expected Behavior:**
What should happen

**Actual Behavior:**
What actually happens

**Environment:**
- Swift: 6.0
- Xcode: 16.0
- Platform: iOS 18.0
- Blend Version: 1.0.0

**Additional Context:**
Any other relevant information
```

### Feature Requests

**Good feature request** includes:
- Clear description of the proposed feature
- Use case and benefits
- Implementation suggestions (optional)
- Mockups or examples (for UI features)

## 🎉 Recognition

Contributors will be:
- Listed in CHANGELOG.md for their contributions
- Recognized in release notes
- Added to a future contributors file
- Invited to join the project maintainer team for significant contributions

## 📞 Getting Help

- **Discussions**: [GitHub Discussions](https://github.com/convenience-init/Blend/discussions)
- **Issues**: [GitHub Issues](https://github.com/convenience-init/Blend/issues)
- **Documentation**: [Blend Docs](./docs/)

Thank you for contributing to Blend! 🚀