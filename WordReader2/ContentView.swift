import SwiftUI
import UniformTypeIdentifiers

enum ReaderTheme: String, CaseIterable {
    case dark, light, device

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "White"
        case .device: return "Device"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .device: return nil
        }
    }
}

private func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

private let readerBackground = adaptiveColor(
    light: .white,
    dark: UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)
)
private let subdued = adaptiveColor(
    light: UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1),
    dark: UIColor(red: 0.64, green: 0.64, blue: 0.68, alpha: 1)
)
private let rule = adaptiveColor(
    light: UIColor(red: 0.87, green: 0.87, blue: 0.89, alpha: 1),
    dark: UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
)
private let highlight = adaptiveColor(
    light: UIColor(red: 0.71, green: 0.12, blue: 0.16, alpha: 1),
    dark: UIColor(red: 0.94, green: 0.27, blue: 0.30, alpha: 1)
)

struct ContentView: View {
    @StateObject private var reader = ReaderModel()
    @AppStorage("readerTheme") private var theme: ReaderTheme = .dark
    @AppStorage("zenMode") private var zenMode = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var importRequested = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 500
            ZStack {
                if zenMode {
                    Button(action: readingAction) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(reader.isLoading)
                    .accessibilityHidden(true)
                }

                VStack(spacing: 0) {
                    header
                    Spacer(minLength: compact ? 4 : 20)
                    Group {
                        if zenMode && reader.book != nil {
                            Button(action: readingAction) {
                                readingWindow
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(reader.isLoading)
                            .accessibilityLabel(readingActionLabel)
                            .accessibilityValue(reader.currentWord)
                        } else {
                            readingWindow
                        }
                    }
                    .frame(height: compact ? max(130, min(210, geometry.size.height - 160)) : 210)
                    Spacer(minLength: compact ? 4 : 20)
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.vertical, compact ? 12 : 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(readerBackground.ignoresSafeArea())
        .foregroundColor(.primary)
        .sheet(isPresented: $showSettings, onDismiss: {
            if importRequested {
                importRequested = false
                showImporter = true
            }
        }) {
            ReaderSettings(reader: reader, theme: $theme, zenMode: $zenMode) {
                importRequested = true
                showSettings = false
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data]
        ) { result in
            switch result {
            case .success(let url): reader.open(url)
            case .failure(let error): reader.errorMessage = "Could not select a file: \(error.localizedDescription)"
            }
        }
        .alert("Book Library", isPresented: Binding(
            get: { reader.errorMessage != nil },
            set: { if !$0 { reader.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { reader.errorMessage = nil }
        } message: {
            Text(reader.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { reader.pause() }
        }
        .preferredColorScheme(theme.colorScheme)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if !zenMode {
                VStack(alignment: .leading, spacing: 5) {
                    Text(reader.book?.title ?? "Word Reader")
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(1)
                    if let chapter = reader.currentChapter {
                        Text(chapter.title)
                            .font(.subheadline)
                            .foregroundColor(subdued)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Button {
                reader.pause()
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(rule, in: Circle())
            }
            .accessibilityLabel("Configuration")
        }
    }

    private var readingWindow: some View {
        VStack(spacing: 0) {
            Rectangle().fill(rule).frame(height: 2)
            Rectangle().fill(rule).frame(width: 2, height: 24)
            Spacer(minLength: 4)
            if reader.isLoading {
                ProgressView().tint(subdued)
            } else if reader.book == nil {
                Button {
                    showImporter = true
                } label: {
                    Text("Open an EPUB to begin")
                        .font(.system(size: 17))
                        .foregroundColor(subdued)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            } else if reader.isFinished {
                Text("Finished")
                    .font(.custom("Georgia", size: 32))
                    .foregroundColor(subdued)
            } else if reader.readingStyle == .flow, let current = reader.currentReadingWord {
                FlowWords(
                    previous: reader.previousReadingWord,
                    current: current,
                    next: reader.nextReadingWord
                )
            } else {
                FocalWord(parts: reader.wordParts)
            }
            Spacer(minLength: 4)
            Rectangle().fill(rule).frame(width: 2, height: 24)
            Rectangle().fill(rule).frame(height: 2)
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            ProgressView(value: reader.progress)
                .tint(highlight)
                .accessibilityLabel("Book progress")
                .accessibilityValue("\(Int(reader.progress * 100)) percent")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(reader.progress * 100))% complete")
                    Text("\(reader.remainingTime) left in \(reader.remainingTimeScope.rawValue)")
                        .foregroundColor(subdued)
                }
                .font(.caption)
                Spacer()
                if !zenMode {
                    Button(action: readingAction) {
                        Label(readingActionLabel, systemImage: reader.isReading ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 20)
                            .frame(height: 42)
                            .background(reader.book == nil ? rule : highlight, in: Capsule())
                            .foregroundColor(reader.book == nil ? .primary : .white)
                    }
                    .disabled(reader.isLoading)
                }
            }
        }
    }

    private var readingActionLabel: String {
        reader.isReading ? "Pause" : reader.isFinished ? "Read again" : "Read"
    }

    private func readingAction() {
        guard !reader.isLoading else { return }
        if reader.book == nil {
            showImporter = true
        } else {
            reader.toggleReading()
        }
    }
}

private struct FocalWord: View {
    let parts: (prefix: String, focal: String, suffix: String)
    var highlighted = true
    var fontSize: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let size = WordMetrics(parts: parts, width: geometry.size.width, fontSize: fontSize).fontSize
            HStack(spacing: 0) {
                Text(parts.prefix)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(parts.focal)
                    .foregroundColor(highlighted ? highlight : .primary)
                Text(parts.suffix)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.custom("Georgia", size: size))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(parts.prefix + parts.focal + parts.suffix)
        }
        .frame(height: 72)
    }
}

struct WordMetrics {
    let fontSize: CGFloat
    let left: CGFloat
    let right: CGFloat

    init(parts: (prefix: String, focal: String, suffix: String), width: CGFloat, fontSize: CGFloat? = nil) {
        let font = UIFont(name: "Georgia", size: 54) ?? .systemFont(ofSize: 54)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let left = (parts.prefix as NSString).size(withAttributes: attributes).width
        let center = (parts.focal as NSString).size(withAttributes: attributes).width
        let right = (parts.suffix as NSString).size(withAttributes: attributes).width
        let required = 2 * max(left, right) + center
        let size = fontSize ?? (required > width ? 54 * max(0, width) / required : 54)
        self.fontSize = size
        self.left = (left + center / 2) * size / 54
        self.right = (right + center / 2) * size / 54
    }
}

struct FlowLayout {
    let fontSize: CGFloat
    let previousOffset: CGFloat
    let nextOffset: CGFloat
    private static let spacing: CGFloat = 14

    init(previous: ReadingWord?, current: ReadingWord, next: ReadingWord?, width: CGFloat) {
        let currentBase = WordMetrics(parts: current.parts, width: .greatestFiniteMagnitude)
        let previousBase = previous.map { WordMetrics(parts: $0.parts, width: .greatestFiniteMagnitude) }
        let nextBase = next.map { WordMetrics(parts: $0.parts, width: .greatestFiniteMagnitude) }
        fontSize = WordMetrics(parts: current.parts, width: width).fontSize
        let scale = fontSize / 54
        previousOffset = -(currentBase.left + (previousBase?.right ?? 0)) * scale - Self.spacing
        nextOffset = (currentBase.right + (nextBase?.left ?? 0)) * scale + Self.spacing
    }
}

private struct FlowWords: View {
    let previous: ReadingWord?
    let current: ReadingWord
    let next: ReadingWord?

    var body: some View {
        GeometryReader { geometry in
            let layout = FlowLayout(previous: previous, current: current, next: next, width: geometry.size.width)
            let words = [previous, current, next].compactMap { $0 }
            ZStack {
                ForEach(words) { word in
                    let isCurrent = word.id == current.id
                    FocalWord(parts: word.parts, highlighted: isCurrent, fontSize: layout.fontSize)
                        .offset(x: isCurrent ? 0 : word.id == previous?.id ? layout.previousOffset : layout.nextOffset)
                        .opacity(isCurrent ? 1 : 0.4)
                }
            }
            .transaction { $0.animation = nil }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current.text)
        }
        .frame(height: 72)
    }
}

private struct ReaderSettings: View {
    @ObservedObject var reader: ReaderModel
    @Binding var theme: ReaderTheme
    @Binding var zenMode: Bool
    let openBook: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button(action: openBook) {
                        Label("Open EPUB from Files", systemImage: "folder")
                    }
                    .disabled(reader.isLoading)
                }

                if !reader.recentBooks.isEmpty {
                    Section("Recent books") {
                        ForEach(reader.recentBooks) { recent in
                            Button {
                                reader.openRecent(recent)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(recent.title)
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                        Text("\(Int(recent.progress * 100))% complete")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(reader.isLoading)
                        }
                    }
                }
                
                if let book = reader.book {
                    Section("Chapter") {
                        NavigationLink {
                            List {
                                ForEach(book.chapters.indices, id: \.self) { index in
                                    Button {
                                        reader.selectChapter(index)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(book.chapters[index].title)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            if index == reader.chapterIndex {
                                                Image(systemName: "checkmark").foregroundColor(highlight)
                                            }
                                        }
                                    }
                                }
                            }
                            .navigationTitle("Chapters")
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                Text("Select chapter")
                                Spacer()
                                Text(reader.currentChapter?.title ?? "")
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .disabled(reader.isLoading)
                    }
                }
                
                Section("Reading speed") {
                    HStack {
                        Text("Words per minute")
                        Spacer()
                        Text("\(reader.wordsPerMinute) wpm")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(reader.wordsPerMinute) },
                        set: { reader.setWordsPerMinute(Int($0)) }
                    ), in: 50...1200, step: 10)
                    .tint(highlight)
                    .accessibilityLabel("Words per minute")
                    HStack {
                        Text("50")
                        Spacer()
                        Text("1,200")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Section("Remaining time") {
                    Picker("Remaining time", selection: Binding(
                        get: { reader.remainingTimeScope },
                        set: { reader.setRemainingTimeScope($0) }
                    )) {
                        ForEach(RemainingTimeScope.allCases, id: \.self) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Appearance") {
                    Toggle("Zen mode", isOn: $zenMode)
                    Picker("Theme", selection: $theme) {
                        ForEach(ReaderTheme.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Reading style") {
                    Picker("Reading style", selection: Binding(
                        get: { reader.readingStyle },
                        set: { reader.setReadingStyle($0) }
                    )) {
                        ForEach(ReadingStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Flow shows the previous and next words alongside the current word.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(highlight)
        .preferredColorScheme(theme.colorScheme)
    }
}
