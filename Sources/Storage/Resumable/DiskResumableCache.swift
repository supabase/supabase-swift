import Foundation

final class DiskResumableCache: ResumableCache, @unchecked Sendable {
    private let storage: FileManager

    init(storage: FileManager) {
        self.storage = storage
    }

    func set(fingerprint: Fingerprint, entry: ResumableCacheEntry) async throws {
        let data = try JSONEncoder().encode(entry)
        storage.createFile(atPath: fingerprint.value, contents: data)
    }

    func get(fingerprint: Fingerprint) async throws -> ResumableCacheEntry? {
        let data = storage.contents(atPath: fingerprint.value)
        guard let data = data else {
            return nil
        }
        return try JSONDecoder().decode(ResumableCacheEntry.self, from: data)
    }

    func remove(fingerprint: Fingerprint) async throws {
        try storage.removeItem(atPath: fingerprint.value)
    }

    func clear() async throws {
        try storage.removeItem(atPath: storage.currentDirectoryPath)
    }

    func entries() async throws -> [CachePair] {
        let files = try storage.contentsOfDirectory(atPath: storage.currentDirectoryPath)
        return try files.compactMap { file -> CachePair? in
            let data = storage.contents(atPath: file)
            guard let data = data else {
                return nil
            }
            return (
                Fingerprint(value: file)!,
                try JSONDecoder().decode(ResumableCacheEntry.self, from: data)
            )
        }
    }
}
