import Foundation

/// Equatable conformance for NetworkError
extension NetworkError: Equatable {
    // MARK: - Equatable Conformance
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        return compareNetworkErrors(lhs: lhs, rhs: rhs)
    }

    /// Helper function to compare HTTP error variants with data and status codes
    private static func compareHTTPErrorVariants(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.httpError(let lhsStatus, let lhsData), .httpError(let rhsStatus, let rhsData)),
            (.badRequest(let lhsData, let lhsStatus), .badRequest(let rhsData, let rhsStatus)),
            (.forbidden(let lhsData, let lhsStatus), .forbidden(let rhsData, let rhsStatus)),
            (.notFound(let lhsData, let lhsStatus), .notFound(let rhsData, let rhsStatus)),
            (.rateLimited(let lhsData, let lhsStatus), .rateLimited(let rhsData, let rhsStatus)),
            (.unauthorized(let lhsData, let lhsStatus), .unauthorized(let rhsData, let rhsStatus)):
            return lhsStatus == rhsStatus && lhsData == rhsData
        default:
            return false
        }
    }

    /// Helper function to compare decoding errors
    private static func compareDecodingErrors(
        lhsError: Error, lhsData: Data?, rhsError: Error, rhsData: Data?
    ) -> Bool {
        let lhsNSError = lhsError as NSError
        let rhsNSError = rhsError as NSError
        return type(of: lhsError) == type(of: rhsError)
            && lhsNSError.domain == rhsNSError.domain && lhsNSError.code == rhsNSError.code
            && lhsData == rhsData
    }

    /// Helper function to compare decoding failed errors
    private static func compareDecodingFailedErrors(
        lhs: DecodingFailedParams, rhs: DecodingFailedParams
    ) -> Bool {
        let lhsNSError = lhs.error as NSError
        let rhsNSError = rhs.error as NSError
        return lhs.reason == rhs.reason && type(of: lhs.error) == type(of: rhs.error)
            && lhsNSError.domain == rhsNSError.domain && lhsNSError.code == rhsNSError.code
            && lhs.data == rhs.data
    }

    /// Helper function to compare simple cases that always return true when matched
    private static func compareSimpleCases(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.networkUnavailable, .networkUnavailable), (.noResponse, .noResponse),
            (.imageProcessingFailed, .imageProcessingFailed),
            (.invalidBodyForGET, .invalidBodyForGET),
            (.requestCancelled, .requestCancelled), (.authenticationFailed, .authenticationFailed):
            return true
        default:
            return false
        }
    }

    /// Helper function to compare cases with single string parameters
    private static func compareStringCases(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidEndpoint(let lhsReason), .invalidEndpoint(let rhsReason)):
            return lhsReason == rhsReason
        case (.badMimeType(let lhsType), .badMimeType(let rhsType)):
            return lhsType == rhsType
        case (.uploadFailed(let lhsMessage), .uploadFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.cacheError(let lhsMessage), .cacheError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    /// Helper function to compare cases with single non-string parameters
    private static func compareSingleParamCases(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.requestTimeout(let lhsDuration), .requestTimeout(let rhsDuration)):
            return lhsDuration == rhsDuration
        case (.transportError(let lhsCode, _), .transportError(let rhsCode, _)):
            return lhsCode == rhsCode
        case (.outOfScriptBounds(let lhsCall), .outOfScriptBounds(let rhsCall)):
            return lhsCall == rhsCall
        default:
            return false
        }
    }

    /// Helper function to compare cases with multiple parameters
    private static func compareMultiParamCases(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (
            .payloadTooLarge(let lhsSize, let lhsLimit), .payloadTooLarge(let rhsSize, let rhsLimit)
        ):
            return lhsSize == rhsSize && lhsLimit == rhsLimit
        case (
            .invalidMockConfiguration(let lhsCallIndex, let lhsMissingData, let lhsMissingResponse),
            .invalidMockConfiguration(let rhsCallIndex, let rhsMissingData, let rhsMissingResponse)
        ):
            return lhsCallIndex == rhsCallIndex && lhsMissingData == rhsMissingData
                && lhsMissingResponse == rhsMissingResponse
        default:
            return false
        }
    }

    /// Compares two NetworkError instances for equality
    private static func compareNetworkErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        // Delegate to category-specific comparison functions
        return compareBasicErrors(lhs: lhs, rhs: rhs) || compareDataErrors(lhs: lhs, rhs: rhs)
            || compareStringErrors(lhs: lhs, rhs: rhs) || compareTransportErrors(lhs: lhs, rhs: rhs)
            || compareHTTPErrors(lhs: lhs, rhs: rhs) || compareSimpleErrors(lhs: lhs, rhs: rhs)
    }

    /// Compare basic errors (custom, server, decoding)
    private static func compareBasicErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (
            .customError(let lhsMessage, let lhsDetails),
            .customError(let rhsMessage, let rhsDetails)
        ):
            return lhsMessage == rhsMessage && lhsDetails == rhsDetails
        case (.serverError(let lhsStatus, let lhsData), .serverError(let rhsStatus, let rhsData)):
            return lhsStatus == rhsStatus && lhsData == rhsData
        default:
            return false
        }
    }

    /// Compare data-related errors (decoding errors)
    private static func compareDataErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.decodingError(let lhsError, let lhsData), .decodingError(let rhsError, let rhsData)):
            return compareDecodingErrors(
                lhsError: lhsError, lhsData: lhsData, rhsError: rhsError, rhsData: rhsData)
        case (
            .decodingFailed(let lhsReason, let lhsError, let lhsData),
            .decodingFailed(let rhsReason, let rhsError, let rhsData)
        ):
            return compareDecodingFailedErrors(
                lhs: DecodingFailedParams(reason: lhsReason, error: lhsError, data: lhsData),
                rhs: DecodingFailedParams(reason: rhsReason, error: rhsError, data: rhsData)
            )
        default:
            return false
        }
    }

    /// Compare string-based errors
    private static func compareStringErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidEndpoint(let lhsReason), .invalidEndpoint(let rhsReason)):
            return lhsReason == rhsReason
        case (.badMimeType(let lhsType), .badMimeType(let rhsType)):
            return lhsType == rhsType
        case (.uploadFailed(let lhsMessage), .uploadFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.cacheError(let lhsMessage), .cacheError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    /// Compare transport and complex errors
    private static func compareTransportErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.transportError(let lhsCode, _), .transportError(let rhsCode, _)):
            return lhsCode == rhsCode
        case (.outOfScriptBounds(let lhsCall), .outOfScriptBounds(let rhsCall)):
            return lhsCall == rhsCall
        case (
            .payloadTooLarge(let lhsSize, let lhsLimit), .payloadTooLarge(let rhsSize, let rhsLimit)
        ):
            return lhsSize == rhsSize && lhsLimit == rhsLimit
        case (
            .invalidMockConfiguration(let lhsCallIndex, let lhsMissingData, let lhsMissingResponse),
            .invalidMockConfiguration(let rhsCallIndex, let rhsMissingData, let rhsMissingResponse)
        ):
            return lhsCallIndex == rhsCallIndex && lhsMissingData == rhsMissingData
                && lhsMissingResponse == rhsMissingResponse
        case (.requestTimeout(let lhsDuration), .requestTimeout(let rhsDuration)):
            return lhsDuration == rhsDuration
        default:
            return false
        }
    }

    /// Compare HTTP error variants
    private static func compareHTTPErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        return compareHTTPErrorVariants(lhs: lhs, rhs: rhs)
    }

    /// Compare simple errors that return true when matched
    private static func compareSimpleErrors(lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.networkUnavailable, .networkUnavailable), (.noResponse, .noResponse),
            (.imageProcessingFailed, .imageProcessingFailed),
            (.invalidBodyForGET, .invalidBodyForGET),
            (.requestCancelled, .requestCancelled), (.authenticationFailed, .authenticationFailed):
            return true
        default:
            return false
        }
    }
}

/// Parameters for decoding failed error comparison
private struct DecodingFailedParams {
    let reason: String
    let error: Error
    let data: Data?
}
