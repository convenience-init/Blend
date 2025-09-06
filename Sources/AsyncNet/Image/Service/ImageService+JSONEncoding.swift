import Foundation

// MARK: - Type-Safe JSON Encoding

/// Dynamic coding keys for handling additional fields in JSON encoding
public struct DynamicCodingKeys: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Type-safe payload structure for base64 image uploads
public struct UploadPayload: Encodable {
    let fieldName: String
    let fileName: String
    let compressionQuality: CGFloat
    let base64Data: String
    let additionalFields: [String: String]

    private enum CodingKeys: String, CodingKey {
        case fieldName
        case fileName
        case compressionQuality
        case base64Data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)

        // Encode standard fields
        try encodeStandardFields(to: &container)

        // Encode additional fields
        try encodeAdditionalFields(to: &container)
    }

    /// Encodes the standard fields (fieldName, fileName, compressionQuality, data)
    private func encodeStandardFields(to container: inout KeyedEncodingContainer<DynamicCodingKeys>) throws {
        // Encode fieldName
        let fieldNameKey = try createCodingKey(for: "fieldName", value: fieldName)
        try container.encode(fieldName, forKey: fieldNameKey)

        // Encode fileName
        let fileNameKey = try createCodingKey(for: "fileName", value: fileName)
        try container.encode(fileName, forKey: fileNameKey)

        // Encode compressionQuality
        let compressionQualityKey = try createCodingKey(
            for: "compressionQuality", value: compressionQuality)
        try container.encode(compressionQuality, forKey: compressionQualityKey)

        // Encode data
        let dataKey = try createCodingKey(for: "data", value: base64Data)
        try container.encode(base64Data, forKey: dataKey)
    }

    /// Encodes additional fields from the dictionary
    private func encodeAdditionalFields(
        to container: inout KeyedEncodingContainer<DynamicCodingKeys>
    ) throws {
        for (key, value) in additionalFields {
            let additionalKey = try createCodingKey(for: key, value: value)
            try container.encode(value, forKey: additionalKey)
        }
    }

    /// Safely creates a coding key for the given field name
    private func createCodingKey<T>(for fieldName: String, value: T) throws -> DynamicCodingKeys {
        guard let key = DynamicCodingKeys(stringValue: fieldName) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for \(fieldName)"
                )
            )
        }
        return key
    }
}
