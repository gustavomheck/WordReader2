import XCTest
import SwiftUI
import ZIPFoundation
@testable import WordReader2

final class ReaderTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "WordReader2Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeLibrary() throws -> BookLibrary {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return BookLibrary(directory: directory)
    }

    func testThemeSelectionMapsToExpectedColorSchemes() {
        XCTAssertEqual(ReaderTheme.dark.colorScheme, .dark)
        XCTAssertEqual(ReaderTheme.light.colorScheme, .light)
        XCTAssertNil(ReaderTheme.device.colorScheme)
        XCTAssertEqual(ReaderTheme.allCases.map(\.title), ["Dark", "White", "Device"])
        XCTAssertEqual(ReaderTheme(rawValue: "device"), .device)
    }

    @MainActor
    func testReadingSpeedPersistsAndStaysWithinBounds() throws {
        let defaults = try makeDefaults()
        let library = try makeLibrary()
        let reader = ReaderModel(library: library, restoreLastBook: false, defaults: defaults)
        XCTAssertEqual(reader.wordsPerMinute, 300)
        reader.setWordsPerMinute(600)
        let relaunched = ReaderModel(library: library, restoreLastBook: false, defaults: defaults)
        XCTAssertEqual(relaunched.wordsPerMinute, 600)
        relaunched.setWordsPerMinute(5000)
        XCTAssertEqual(ReaderModel(library: library, restoreLastBook: false, defaults: defaults).wordsPerMinute, 1200)
        relaunched.setWordsPerMinute(0)
        XCTAssertEqual(ReaderModel(library: library, restoreLastBook: false, defaults: defaults).wordsPerMinute, 50)
        defaults.set(5000, forKey: "wordsPerMinute")
        XCTAssertEqual(ReaderModel(library: library, restoreLastBook: false, defaults: defaults).wordsPerMinute, 1200)
    }

    @MainActor
    func testReadingStylePersistsAndDefaultsToFlash() throws {
        let defaults = try makeDefaults()
        let library = try makeLibrary()
        let reader = ReaderModel(library: library, restoreLastBook: false, defaults: defaults)
        XCTAssertEqual(reader.readingStyle, .flash)
        reader.setReadingStyle(.flow)
        let relaunched = ReaderModel(library: library, restoreLastBook: false, defaults: defaults)
        XCTAssertEqual(relaunched.readingStyle, .flow)
        relaunched.setReadingStyle(.flash)
        XCTAssertEqual(ReaderModel(library: library, restoreLastBook: false, defaults: defaults).readingStyle, .flash)
    }

    func testFlowLayoutFitsNeighborsWithoutOverlap() {
        let previous = ReadingWord(id: .init(chapter: 0, index: 0), text: "beautiful")
        let current = ReadingWord(id: .init(chapter: 0, index: 1), text: "reading")
        let next = ReadingWord(id: .init(chapter: 0, index: 2), text: "experience")
        for width: CGFloat in [320, 390, 700] {
            let layout = FlowLayout(previous: previous, current: current, next: next, width: width)
            let left = WordMetrics(parts: previous.parts, width: width, fontSize: layout.fontSize)
            let center = WordMetrics(parts: current.parts, width: width, fontSize: layout.fontSize)
            let right = WordMetrics(parts: next.parts, width: width, fontSize: layout.fontSize)
            XCTAssertGreaterThanOrEqual(layout.previousOffset - left.left, -width / 2 - 0.01)
            XCTAssertLessThanOrEqual(layout.nextOffset + right.right, width / 2 + 0.01)
            XCTAssertLessThan(layout.previousOffset + left.right, -center.left)
            XCTAssertGreaterThan(layout.nextOffset - right.left, center.right)
            XCTAssertLessThanOrEqual(layout.fontSize, 54)
        }
    }

    @MainActor
    func testFlowNeighborsAcrossChapterBoundaries() async throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = ReaderModel(library: try makeLibrary(), restoreLastBook: false, defaults: try makeDefaults())
        reader.open(url)
        for _ in 0..<100 where reader.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(reader.previousReadingWord)
        XCTAssertEqual(reader.currentReadingWord?.text, "Second")
        XCTAssertEqual(reader.nextReadingWord?.text, "or")
        reader.selectChapter(1)
        XCTAssertEqual(reader.previousReadingWord?.text, "into")
        XCTAssertEqual(reader.currentReadingWord?.text, "First")
        XCTAssertEqual(reader.nextReadingWord?.text, "last")
        reader.setReadingStyle(.flow)
        reader.setWordsPerMinute(1200)
        reader.toggleReading()
        for _ in 0..<100 where reader.isReading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(reader.isFinished)
        XCTAssertNil(reader.currentReadingWord)
        XCTAssertNil(reader.previousReadingWord)
        XCTAssertNil(reader.nextReadingWord)
    }

    private func makeBook(title: String = "Test &amp; Book") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        let archive = try Archive(url: url, accessMode: .create)
        let files = [
            "META-INF/container.xml": """
                <container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>
                """,
            "OPS/book.opf": """
                <package xmlns:dc="http://purl.org/dc/elements/1.1/">
                  <metadata><dc:title>\(title)</dc:title></metadata>
                  <manifest>
                    <item id="first" href="Text/first%20chapter.xhtml" media-type="application/xhtml+xml"/>
                    <item id="second" href="Text/second.xhtml" media-type="application/xhtml+xml"/>
                    <item id="extra" href="Text/extra.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine><itemref idref="second"/><itemref idref="extra" linear="no"/><itemref idref="first"/></spine>
                </package>
                """,
            "OPS/Text/first chapter.xhtml": "<html><body><h1>First</h1><p>last word.</p></body></html>",
            "OPS/Text/second.xhtml": "<html><body><h1>Second</h1><script>hidden</script><p>or &amp; into</p></body></html>",
            "OPS/Text/extra.xhtml": "<html><body>Not in the reading order</body></html>"
        ]
        for (path, text) in files {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, size in
                data.subdata(in: Int(offset)..<(Int(offset) + size))
            }
        }
        return url
    }

    func testImportUsesSpineOrderAndDecodesText() throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try EpubBookService.load(from: url)
        XCTAssertEqual(book.title, "Test & Book")
        XCTAssertEqual(book.chapters.map(\.title), ["Second", "First"])
        XCTAssertEqual(book.chapters[0].words, ["Second", "or", "&", "into"])
        XCTAssertEqual(book.chapters[1].words, ["First", "last", "word."])
    }

    func testInvalidArchiveIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try Data("not an epub".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try EpubBookService.load(from: url))
    }

    @MainActor
    func testReadingTransitionsCompletionAndRestart() async throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = ReaderModel(library: try makeLibrary(), restoreLastBook: false, defaults: try makeDefaults())
        reader.open(url)
        for _ in 0..<100 where reader.isLoading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.currentWord, "Second")
        XCTAssertEqual(reader.wordParts.focal, "c")
        reader.selectChapter(1)
        XCTAssertEqual(reader.currentWord, "First")
        XCTAssertEqual(reader.progress, 4.0 / 7.0, accuracy: 0.0001)
        reader.setWordsPerMinute(1200)
        reader.toggleReading()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(reader.isFinished)
        XCTAssertFalse(reader.isReading)
        XCTAssertEqual(reader.progress, 1)
        reader.toggleReading()
        XCTAssertEqual(reader.currentWord, "Second")
        XCTAssertTrue(reader.isReading)
        reader.pause()
    }

    @MainActor
    func testFailedImportKeepsCurrentBook() async throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = ReaderModel(library: try makeLibrary(), restoreLastBook: false, defaults: try makeDefaults())
        reader.open(url)
        for _ in 0..<100 where reader.isLoading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        reader.open(url.appendingPathExtension("missing"))
        for _ in 0..<100 where reader.isLoading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertEqual(reader.book?.title, "Test & Book")
        XCTAssertEqual(reader.currentWord, "Second")
    }

    @MainActor
    func testPlaybackAdvancesToNextChapterAndPauseStopsIt() async throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = ReaderModel(library: try makeLibrary(), restoreLastBook: false, defaults: try makeDefaults())
        reader.open(url)
        for _ in 0..<100 where reader.isLoading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        reader.setWordsPerMinute(5000)
        XCTAssertEqual(reader.wordsPerMinute, 1200)
        reader.toggleReading()
        for _ in 0..<100 where reader.chapterIndex == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        reader.pause()
        XCTAssertEqual(reader.chapterIndex, 1)
        let position = reader.wordIndex
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(reader.wordIndex, position)
        XCTAssertFalse(reader.isReading)
    }

    @MainActor
    func testLibraryRestoresPositionsAndDeduplicatesImports() async throws {
        let first = try makeBook()
        let second = try makeBook(title: "Another Book")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let library = try makeLibrary()
        let reader = ReaderModel(library: library, restoreLastBook: false, defaults: try makeDefaults())
        reader.open(first)
        for _ in 0..<100 where reader.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(reader.errorMessage)
        reader.selectChapter(1)
        let firstID = try XCTUnwrap(reader.recentBooks.first?.id)
        reader.open(second)
        for _ in 0..<100 where reader.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.recentBooks.count, 2)
        let secondID = try XCTUnwrap(reader.recentBooks.first?.id)
        XCTAssertNotEqual(firstID, secondID)
        reader.selectChapter(0)
        let firstRecent = try XCTUnwrap(reader.recentBooks.first { $0.id == firstID })
        reader.openRecent(firstRecent)
        for _ in 0..<100 where reader.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(reader.chapterIndex, 1)
        XCTAssertEqual(reader.currentWord, "First")
        try FileManager.default.removeItem(at: first)

        let relaunched = ReaderModel(library: library, defaults: try makeDefaults())
        for _ in 0..<100 where relaunched.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(relaunched.errorMessage)
        XCTAssertEqual(relaunched.chapterIndex, 1)
        XCTAssertEqual(relaunched.currentWord, "First")
        let savedSecond = try XCTUnwrap(relaunched.recentBooks.first { $0.id == secondID })
        relaunched.openRecent(savedSecond)
        for _ in 0..<100 where relaunched.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(relaunched.chapterIndex, 0)
        relaunched.open(second)
        for _ in 0..<100 where relaunched.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(relaunched.recentBooks.count, 2)
        XCTAssertEqual(relaunched.recentBooks.first?.id, secondID)
    }

    @MainActor
    func testCompletedBookRestoresAsFinished() async throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let library = try makeLibrary()
        let reader = ReaderModel(library: library, restoreLastBook: false, defaults: try makeDefaults())
        reader.open(url)
        for _ in 0..<100 where reader.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        reader.selectChapter(1)
        reader.setWordsPerMinute(1200)
        reader.toggleReading()
        for _ in 0..<100 where reader.isReading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(reader.isFinished)
        let relaunched = ReaderModel(library: library, defaults: try makeDefaults())
        for _ in 0..<100 where relaunched.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(relaunched.isFinished)
        XCTAssertEqual(relaunched.progress, 1)
    }

    @MainActor
    func testProgressIsCheckpointedWhileReading() async throws {
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let library = try makeLibrary()
        let reader = ReaderModel(library: library, restoreLastBook: false, defaults: try makeDefaults())
        reader.open(url)
        for _ in 0..<100 where reader.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        reader.setWordsPerMinute(50)
        reader.toggleReading()
        for _ in 0..<200 where reader.wordIndex == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(reader.isReading)
        XCTAssertEqual(reader.wordIndex, 1)
        let saved = try XCTUnwrap(try library.loadIndex().first)
        XCTAssertEqual(saved.wordIndex, 1)
        reader.pause()
        let relaunched = ReaderModel(library: library, defaults: try makeDefaults())
        for _ in 0..<100 where relaunched.isLoading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(relaunched.wordIndex, 1)
        XCTAssertEqual(relaunched.currentWord, "or")
    }

    @MainActor
    func testCorruptLibraryIsReportedAndNotOverwritten() async throws {
        let library = try makeLibrary()
        let index = library.directory.appendingPathComponent("library.json")
        let corrupt = Data("invalid library".utf8)
        try corrupt.write(to: index)
        let reader = ReaderModel(library: library, defaults: try makeDefaults())
        XCTAssertNotNil(reader.errorMessage)
        let url = try makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        reader.open(url)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertEqual(try Data(contentsOf: index), corrupt)
    }
}
