import Foundation
import SwiftSoup
import ZIPFoundation

struct ReadingChapter {
    let title: String
    let words: [String]
}

struct EpubBook {
    let title: String
    let chapters: [ReadingChapter]
}

enum EpubError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return NSLocalizedString(message, comment: "EPUB error")
        }
    }
}

enum EpubBookService {
    private static let maximumEntrySize: UInt64 = 32 * 1024 * 1024

    static func load(from url: URL, fallbackTitle: String? = nil) throws -> EpubBook {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let archive = try Archive(url: url, accessMode: .read)
        let container = try xml(read("META-INF/container.xml", from: archive))
        guard let rootfile = try container.getElementsByTag("rootfile").first() else {
            throw EpubError.invalid("This EPUB has no package document.")
        }
        let packagePath = try rootfile.attr("full-path")
        guard !packagePath.isEmpty else {
            throw EpubError.invalid("This EPUB has an invalid package path.")
        }

        let package = try xml(read(packagePath, from: archive))
        let title = try package.getAllElements().array()
            .first { $0.tagName().lowercased() == "dc:title" }?
            .text()
        var manifest: [String: (href: String, mediaType: String)] = [:]
        for item in try package.getElementsByTag("item").array() {
            manifest[try item.attr("id")] = (try item.attr("href"), try item.attr("media-type"))
        }

        var chapters: [ReadingChapter] = []
        for reference in try package.getElementsByTag("itemref").array() {
            if try reference.attr("linear").lowercased() == "no" { continue }
            let id = try reference.attr("idref")
            guard let item = manifest[id] else {
                throw EpubError.invalid("The EPUB reading order refers to a missing chapter.")
            }
            guard item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html" else {
                throw EpubError.invalid("This EPUB contains an unsupported reading-order item.")
            }
            let path = try resolve(item.href, relativeTo: packagePath)
            let html = try read(path, from: archive)
            let document = try SwiftSoup.parse(html)
            try document.select("script, style, svg, nav").remove()
            let content = try document.body()?.text() ?? ""
            let words = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.isEmpty else { continue }
            let heading = try document.select("h1, h2").first()?.text()
            let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            chapters.append(ReadingChapter(title: heading?.isEmpty == false ? heading! : fallback, words: words))
        }

        guard !chapters.isEmpty else {
            throw EpubError.invalid("No readable text was found in this EPUB.")
        }
        return EpubBook(
            title: title?.isEmpty == false ? title! : (fallbackTitle ?? url.deletingPathExtension().lastPathComponent),
            chapters: chapters
        )
    }

    private static func xml(_ text: String) throws -> Document {
        try SwiftSoup.parse(text, "", Parser.xmlParser())
    }

    private static func read(_ path: String, from archive: Archive) throws -> String {
        guard let entry = archive[path], entry.type == .file else {
            throw EpubError.invalid(String(format: NSLocalizedString("The EPUB is missing %@.", comment: "Missing EPUB file"), path))
        }
        guard entry.uncompressedSize <= maximumEntrySize else {
            throw EpubError.invalid("An EPUB file is too large to open safely.")
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard UInt64(data.count) + UInt64(chunk.count) <= maximumEntrySize else {
                throw EpubError.invalid("An EPUB file is too large to open safely.")
            }
            data.append(chunk)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw EpubError.invalid("An EPUB text file uses an unsupported encoding.")
        }
        return text
    }

    private static func resolve(_ href: String, relativeTo packagePath: String) throws -> String {
        guard let components = URLComponents(string: href),
              components.scheme == nil, components.host == nil,
              let decoded = components.percentEncodedPath.removingPercentEncoding,
              !decoded.hasPrefix("/") else {
            throw EpubError.invalid("The EPUB contains an invalid chapter path.")
        }
        var parts = packagePath.split(separator: "/").dropLast().map(String.init)
        for component in decoded.split(separator: "/") {
            switch component {
            case ".", "": continue
            case "..":
                guard !parts.isEmpty else {
                    throw EpubError.invalid("The EPUB contains an invalid chapter path.")
                }
                parts.removeLast()
            default: parts.append(String(component))
            }
        }
        return parts.joined(separator: "/")
    }
}
