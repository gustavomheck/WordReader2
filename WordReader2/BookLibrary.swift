import CryptoKit
import Foundation

struct RecentBook: Codable, Identifiable {
    let id: String
    var title: String
    var chapterIndex: Int
    var wordIndex: Int
    var progress: Double
    var lastOpened: Date
}

final class BookLibrary {
    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookLibrary", isDirectory: true)
    }

    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    func loadIndex() throws -> [RecentBook] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([RecentBook].self, from: Data(contentsOf: indexURL))
    }

    func saveIndex(_ books: [RecentBook]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(books).write(to: indexURL, options: .atomic)
    }

    func bookURL(for id: String) throws -> URL {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw EpubError.invalid("The saved book identifier is invalid.")
        }
        return directory.appendingPathComponent(id + ".epub")
    }

    func importBook(from source: URL) throws -> (id: String, book: EpubBook) {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer {
            if fileManager.fileExists(atPath: temporary.path) {
                do { try fileManager.removeItem(at: temporary) }
                catch { NSLog("Could not remove temporary EPUB: %@", error.localizedDescription) }
            }
        }

        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do {
                try fileManager.copyItem(at: url, to: temporary)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }

        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data)
        }
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let book = try EpubBookService.load(
            from: temporary,
            fallbackTitle: source.deletingPathExtension().lastPathComponent
        )
        let destination = try bookURL(for: id)
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        return (id, book)
    }
}
