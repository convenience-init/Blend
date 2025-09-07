import Foundation

/// Test and mock error message handlers for NetworkError
public enum TestErrorMessages {
    /// Returns test error descriptions
    public static func testErrorDescription(for error: NetworkError) -> String {
        switch error {
        case .outOfScriptBounds(let call):
            return outOfScriptBoundsDescription(call)
        case .payloadTooLarge(let size, let limit):
            return payloadTooLargeDescription(size, limit)
        case .invalidMockConfiguration(let callIndex, let missingData, let missingResponse):
            return mockConfigDesc(callIndex, missingData, missingResponse)
        default:
            return "Unknown test error"
        }
    }

    private static func outOfScriptBoundsDescription(_ call: Int) -> String {
        return String(
            format: NSLocalizedString(
                "Out of script bounds: Call %d", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Out of script bounds: Call %d",
                comment: "Error message for out-of-script-bounds with call number"), call)
    }

    private static func payloadTooLargeDescription(_ size: Int, _ limit: Int) -> String {
        return String(
            format: NSLocalizedString(
                "Payload too large: %d B exceeds %d B limit.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Payload too large: %d B exceeds %d B limit.",
                comment: "Error message for payload too large"),
            size, limit)
    }

    private static func mockConfigDesc(
        _ callIndex: Int, _ missingData: Bool, _ missingResponse: Bool
    ) -> String {
        var missingComponents: [String] = []
        if missingData { missingComponents.append("data") }
        if missingResponse { missingComponents.append("response") }
        let componentsString = missingComponents.joined(separator: " and ")
        return String(
            format: NSLocalizedString(
                "Test configuration error at call %d: missing %@.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Test configuration error at call %d: missing %@.",
                comment: "Error message for test configuration errors with details"
            ),
            callIndex, componentsString
        )
    }
}
