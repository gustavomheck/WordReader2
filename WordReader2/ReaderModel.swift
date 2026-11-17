import Foundation
import Combine

@MainActor
final class ReaderModel: ObservableObject {
    @Published private(set) var book: EpubBook?
    @Published private(set) var chapterIndex = 0
    @Published private(set) var wordIndex = 0
    @Published private(set) var isReading = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var wordsPerMinute = 300
    @Published private(set) var recentBooks: [RecentBook] = []

    private let library: BookLibrary
    private var currentBookID: String?
    private var libraryAvailable = true
    private var lastSave = Date.distantPast
    private var readingTask: Task<Void, Never>?
    private var totalWords = 0

    init(library: BookLibrary = BookLibrary(), restoreLastBook: Bool = true) {
        self.library = library
        do {
            recentBooks = try library.loadIndex().sorted { $0.lastOpened > $1.lastOpened }
            if restoreLastBook, let recent = recentBooks.first {
                openRecent(recent)
            }
        } catch {
            libraryAvailable = false
            errorMessage = "Could not load your saved books: \(error.localizedDescription)"
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
        let word = Array(currentWord)
        guard !word.isEmpty else { return ("", "", "") }
        let index = word.count <= 1 ? 0 : word.count <= 5 ? 1 : word.count <= 9 ? 2 : 3
        return (String(word[..<index]), String(word[index]), String(word[(index + 1)...]))
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
        guard let chapter = currentChapter else { return "--:--" }
        let seconds = Int(ceil(Double(chapter.words.count - wordIndex) * 60 / Double(wordsPerMinute)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func open(_ url: URL) {
        guard !isLoading else { return }
        pause()
        guard libraryAvailable else {
            errorMessage = "Your saved library could not be loaded. Restart the app before importing another book."
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
                errorMessage = "Could not open EPUB: \(error.localizedDescription)"
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
                errorMessage = "Could not open saved book: \(error.localizedDescription)"
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
        if isReading { startTimer() }
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
            errorMessage = "Could not save reading progress: \(error.localizedDescription)"
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
