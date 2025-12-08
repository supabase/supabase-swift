import Foundation

extension JSONDecoder.DateDecodingStrategy {
    /// A custom date decoding strategy that handles ISO8601 formatted dates with optional fractional seconds.
    ///
    /// This strategy attempts to parse dates in the following order:
    /// 1. ISO8601 with fractional seconds
    /// 2. ISO8601 without fractional seconds
    ///
    /// If both parsing attempts fail, it throws a `DecodingError.dataCorruptedError`.
    ///
    /// - Returns: A `DateDecodingStrategy` that can be used with a `JSONDecoder`.
    static let iso8601WithFractionalSeconds = custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]

        if let date = formatter.date(from: string) {
            return date
        }

        // Try again without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]

        guard let date = formatter.date(from: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(string)"
            )
        }

        return date
    }
}
