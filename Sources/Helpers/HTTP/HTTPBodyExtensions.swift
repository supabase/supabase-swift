import Foundation
import HTTPTypes

extension HTTPBody {
    /// Decodes the body into a decodable object.
    ///
    /// - Parameters:
    ///   - type: The type to decode the body into.
    ///   - decoder: The decoder to use to decode the body.
    /// - Returns: The decoded object.
    /// - Throws: An error if the body cannot be decoded.
    package func decoded<T: Decodable>(
        as _: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await decoder.decode(T.self, from: data)
    }

    /// The data of the body.
    ///
    /// This is a lazy property that will collect the data from the body.
    ///
    /// - Returns: The data of the body.
    /// - Throws: An error if the data cannot be collected.
    package var data: Data {
        get async throws {
            try await Data(collecting: self, upTo: .max)
        }
    }
}
