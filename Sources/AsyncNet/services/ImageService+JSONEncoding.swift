import Foundation

// MARK: - Type-Safe JSON Encoding

/// Dynamic coding keys for handling additional fields in JSON encoding
struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Type-safe payload structure for base64 image uploads
struct UploadPayload: Encodable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)

        // Encode standard fields with safe key creation
        guard let fieldNameKey = DynamicCodingKeys(stringValue: "fieldName") else {
            throw EncodingError.invalidValue(
                "fieldName",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for fieldName"
                )
            )
        }
        try container.encode(fieldName, forKey: fieldNameKey)

        guard let fileNameKey = DynamicCodingKeys(stringValue: "fileName") else {
            throw EncodingError.invalidValue(
                "fileName",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for fileName"
                )
            )
        }
        try container.encode(fileName, forKey: fileNameKey)

        guard let compressionQualityKey = DynamicCodingKeys(stringValue: "compressionQuality")
        else {
            throw EncodingError.invalidValue(
                "compressionQuality",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for compressionQuality"
                )
            )
        }
        try container.encode(compressionQuality, forKey: compressionQualityKey)

        guard let dataKey = DynamicCodingKeys(stringValue: "data") else {
            throw EncodingError.invalidValue(
                "data",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for data"
                )
            )
        }
        try container.encode(base64Data, forKey: dataKey)

        // Encode additional fields with safe key creation
        for (key, value) in additionalFields {
            guard let additionalKey = DynamicCodingKeys(stringValue: key) else {
                throw EncodingError.invalidValue(
                    key,
                    EncodingError.Context(
                        codingPath: [],
                        debugDescription:
                            "Failed to create coding key for additional field '\(key)'"
                    )
                )
            }
            try container.encode(value, forKey: additionalKey)
        }
    }
}
