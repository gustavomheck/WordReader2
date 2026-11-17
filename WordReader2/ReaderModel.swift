import Foundation
import Combine

enum ReadingStyle: String, CaseIterable {
    case flash, flow

    var title: String {
        switch self {
        case .flash: return NSLocalizedString("Flash", comment: "Reading style")
        case .flow: return NSLocalizedString("Flow", comment: "Reading style")
        }
    }
}

enum RemainingTimeScope: String, CaseIterable {
    case chapter, book

    var title: String {
        switch self {
        case .chapter: return NSLocalizedString("Chapter", comment: "Remaining time")
        case .book: return NSLocalizedString("Book", comment: "Remaining time")
        }
    }
}

enum ReaderAccent: String, CaseIterable {
    case red, orange, green, blue, purple, pink

    var title: String {
        switch self {
        case .red: return NSLocalizedString("Red", comment: "Accent color")
        case .orange: return NSLocalizedString("Orange", comment: "Accent color")
        case .green: return NSLocalizedString("Green", comment: "Accent color")
        case .blue: return NSLocalizedString("Blue", comment: "Accent color")
        case .purple: return NSLocalizedString("Purple", comment: "Accent color")
        case .pink: return NSLocalizedString("Pink", comment: "Accent color")
        }
    }
}

struct ReadingWord: Identifiable {
    struct ID: Hashable {
        let chapter: Int
        let index: Int
    }

    let id: ID
    let text: String

    var parts: (prefix: String, focal: String, suffix: String) {
        let word = Array(text)
        guard !word.isEmpty else { return ("", "", "") }
        let index = word.count <= 1 ? 0 : word.count <= 5 ? 1 : word.count <= 9 ? 2 : 3
        return (String(word[..<index]), String(word[index]), String(word[(index + 1)...]))
    }
}

@MainActor
final class ReaderModel: ObservableObject {
    @Published private(set) var book: EpubBook?
    @Published private(set) var chapterIndex = 0
    @Published private(set) var wordIndex = 0
    @Published private(set) var isReading = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var wordsPerMinute = 300
    @Published private(set) var readingStyle: ReadingStyle = .flash
    @Published private(set) var remainingTimeScope: RemainingTimeScope = .chapter
    @Published private(set) var accent: ReaderAccent = .red
    @Published private(set) var recentBooks: [RecentBook] = []

    private static let wordsPerMinuteKey = "wordsPerMinute"
    private static let readingStyleKey = "readingStyle"
    private static let remainingTimeScopeKey = "remainingTimeScope"
    private static let accentKey = "readerAccent"
    private let defaults: UserDefaults
    private let library: BookLibrary
    private var currentBookID: String?
    private var libraryAvailable = true
    private var lastSave = Date.distantPast
    private var readingTask: Task<Void, Never>?
    private var totalWords = 0

    init(library: BookLibrary = BookLibrary(), restoreLastBook: Bool = true,
         defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.wordsPerMinuteKey) as? Int {
            wordsPerMinute = min(1200, max(50, stored))
        }
        if let stored = defaults.string(forKey: Self.readingStyleKey),
           let style = ReadingStyle(rawValue: stored) {
            readingStyle = style
        }
        if let stored = defaults.string(forKey: Self.remainingTimeScopeKey),
           let scope = RemainingTimeScope(rawValue: stored) {
            remainingTimeScope = scope
        }
        if let stored = defaults.string(forKey: Self.accentKey),
           let accent = ReaderAccent(rawValue: stored) {
            self.accent = accent
        }
        do {
            recentBooks = try library.loadIndex().sorted { $0.lastOpened > $1.lastOpened }
            if restoreLastBook, let recent = recentBooks.first {
                openRecent(recent)
            }
        } catch {
            libraryAvailable = false
            errorMessage = String(format: NSLocalizedString("Could not load your saved books: %@", comment: ""), error.localizedDescription)
        }
    }

    var currentChapter: ReadingChapter? {
        guard let book = book, book.chapters.indices.contains(chapterIndex) else { return nil }
        return book.chapters[chapterIndex]
    }

    var currentWord: String {
        guard let chapter = currentChapter, chapter.words.indices.contains(wordIndex) else { return "" }
        return chapter.words[wordIndex]
    }

    var wordParts: (prefix: String, focal: String, suffix: String) {
        currentReadingWord?.parts ?? ("", "", "")
    }

    var currentReadingWord: ReadingWord? {
        readingWord(chapter: chapterIndex, index: wordIndex)
    }

    var previousReadingWord: ReadingWord? {
        guard currentReadingWord != nil, let book = book else { return nil }
        if wordIndex > 0 {
            return readingWord(chapter: chapterIndex, index: wordIndex - 1)
        }
        guard chapterIndex > 0 else { return nil }
        let previousChapter = chapterIndex - 1
        return readingWord(chapter: previousChapter, index: book.chapters[previousChapter].words.count - 1)
    }

    var nextReadingWord: ReadingWord? {
        guard currentReadingWord != nil, let book = book, let chapter = currentChapter else { return nil }
        if wordIndex + 1 < chapter.words.count {
            return readingWord(chapter: chapterIndex, index: wordIndex + 1)
        }
        guard chapterIndex + 1 < book.chapters.count else { return nil }
        return readingWord(chapter: chapterIndex + 1, index: 0)
    }

    private func readingWord(chapter: Int, index: Int) -> ReadingWord? {
        guard let book = book, book.chapters.indices.contains(chapter),
              book.chapters[chapter].words.indices.contains(index) else { return nil }
        return ReadingWord(id: .init(chapter: chapter, index: index), text: book.chapters[chapter].words[index])
    }

    var isFinished: Bool {
        guard let book = book, let chapter = currentChapter else { return false }
        return chapterIndex == book.chapters.count - 1 && wordIndex == chapter.words.count
    }

    var progress: Double {
        guard let book = book, totalWords > 0 else { return 0 }
        let preceding = book.chapters.prefix(chapterIndex).reduce(0) { $0 + $1.words.count }
        return Double(preceding + wordIndex) / Double(totalWords)
    }

    var remainingTime: String {
        guard let chapter = currentChapter, let book = book else { return "--:--" }
        let remainingWords: Int
        switch remainingTimeScope {
        case .chapter:
            remainingWords = chapter.words.count - wordIndex
        case .book:
            let preceding = book.chapters.prefix(chapterIndex).reduce(0) { $0 + $1.words.count }
            remainingWords = totalWords - preceding - wordIndex
        }
        let seconds = Int(ceil(Double(remainingWords) * 60 / Double(wordsPerMinute)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func open(_ url: URL) {
        guard !isLoading else { return }
        pause()
        guard libraryAvailable else {
            errorMessage = NSLocalizedString("Your saved library could not be loaded. Restart the app before importing another book.", comment: "")
            return
        }
        isLoading = true
        Task {
            do {
                let library = self.library
                let imported = try await Task.detached(priority: .userInitiated) {
                    try library.importBook(from: url)
                }.value
                try activate(imported.book, id: imported.id)
            } catch {
                errorMessage = String(format: NSLocalizedString("Could not open EPUB: %@", comment: ""), error.localizedDescription)
            }
            isLoading = false
        }
    }

    func openRecent(_ recent: RecentBook) {
        guard !isLoading, libraryAvailable else { return }
        pause()
        isLoading = true
        Task {
            do {
                let url = try library.bookURL(for: recent.id)
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try EpubBookService.load(from: url, fallbackTitle: recent.title)
                }.value
                try activate(loaded, id: recent.id)
            } catch {
                errorMessage = String(format: NSLocalizedString("Could not open saved book: %@", comment: ""), error.localizedDescription)
            }
            isLoading = false
        }
    }

    private func activate(_ loaded: EpubBook, id: String) throws {
        var entries = recentBooks
        let previous = entries.first { $0.id == id }
        let chapter = previous?.chapterIndex ?? 0
        let word = previous?.wordIndex ?? 0
        guard loaded.chapters.indices.contains(chapter), word >= 0,
              word < loaded.chapters[chapter].words.count ||
                (chapter == loaded.chapters.count - 1 && word == loaded.chapters[chapter].words.count) else {
            throw EpubError.invalid("The saved reading position is invalid.")
        }
        entries.removeAll { $0.id == id }
        entries.insert(RecentBook(id: id, title: loaded.title, chapterIndex: chapter, wordIndex: word,
                                  progress: previous?.progress ?? 0, lastOpened: Date()), at: 0)
        try library.saveIndex(entries)
        recentBooks = entries
        currentBookID = id
        book = loaded
        totalWords = loaded.chapters.reduce(0) { $0 + $1.words.count }
        chapterIndex = chapter
        wordIndex = word
        lastSave = Date()
    }

    func selectChapter(_ index: Int) {
        guard let book = book, book.chapters.indices.contains(index) else { return }
        pause()
        chapterIndex = index
        wordIndex = 0
        saveProgress()
    }

    func setWordsPerMinute(_ value: Int) {
        let bounded = min(1200, max(50, value))
        guard bounded != wordsPerMinute else { return }
        wordsPerMinute = bounded
        defaults.set(bounded, forKey: Self.wordsPerMinuteKey)
        if isReading { startTimer() }
    }

    func setReadingStyle(_ style: ReadingStyle) {
        guard style != readingStyle else { return }
        readingStyle = style
        defaults.set(style.rawValue, forKey: Self.readingStyleKey)
    }

    func setRemainingTimeScope(_ scope: RemainingTimeScope) {
        guard scope != remainingTimeScope else { return }
        remainingTimeScope = scope
        defaults.set(scope.rawValue, forKey: Self.remainingTimeScopeKey)
    }

    func setAccent(_ accent: ReaderAccent) {
        guard accent != self.accent else { return }
        self.accent = accent
        defaults.set(accent.rawValue, forKey: Self.accentKey)
    }

    func toggleReading() {
        guard book != nil, !isLoading else { return }
        if isReading {
            pause()
        } else {
            if isFinished {
                chapterIndex = 0
                wordIndex = 0
                saveProgress()
            }
            isReading = true
            startTimer()
        }
    }

    func pause() {
        readingTask?.cancel()
        readingTask = nil
        isReading = false
        saveProgress()
    }

    private func saveProgress() {
        guard libraryAvailable, let id = currentBookID,
              let index = recentBooks.firstIndex(where: { $0.id == id }) else { return }
        recentBooks[index].chapterIndex = chapterIndex
        recentBooks[index].wordIndex = wordIndex
        recentBooks[index].progress = progress
        do {
            try library.saveIndex(recentBooks)
            lastSave = Date()
        } catch {
            readingTask?.cancel()
            readingTask = nil
            isReading = false
            errorMessage = String(format: NSLocalizedString("Could not save reading progress: %@", comment: ""), error.localizedDescription)
        }
    }

    private func startTimer() {
        readingTask?.cancel()
        let interval = UInt64(60_000_000_000 / wordsPerMinute)
        readingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard let self = self, !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    private func advance() {
        guard let book = book, let chapter = currentChapter else {
            pause()
            return
        }
        wordIndex += 1
        if wordIndex >= chapter.words.count {
            if chapterIndex + 1 < book.chapters.count {
                chapterIndex += 1
                wordIndex = 0
            } else {
                pause()
            }
        }
        if isReading && Date().timeIntervalSince(lastSave) >= 1 {
            saveProgress()
        }
    }
}
