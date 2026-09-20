import AppKit

/// One thing dragged onto an agent window, reduced to what an agent can use.
enum DropItem: Equatable {
    case file(URL)
    case image(Data, ext: String)
    case link(URL)
    case text(String)
}

/// Pure pasteboard classification: no UI, no disk, so it can be checked headless.
enum DropClassifier {
    static let png = NSPasteboard.PasteboardType.png
    static let tiff = NSPasteboard.PasteboardType.tiff

    /// Everything a window registers for. File promises are added by the drop view.
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, png, tiff, .URL, .string]

    /// Order matters: a real file beats its preview image, and image data beats the
    /// address it came from (a picture dragged out of a browser carries both).
    static func classify(_ item: NSPasteboardItem) -> DropItem? {
        let types = item.types
        if types.contains(.fileURL), let s = item.string(forType: .fileURL), let url = URL(string: s), url.isFileURL {
            return .file(URL(fileURLWithPath: url.path))
        }
        if types.contains(png), let data = item.data(forType: png), !data.isEmpty {
            return .image(data, ext: "png")
        }
        if types.contains(tiff), let data = item.data(forType: tiff), !data.isEmpty {
            return .image(data, ext: "tiff")
        }
        if types.contains(.URL), let s = item.string(forType: .URL), let url = URL(string: s) {
            return url.isFileURL ? .file(URL(fileURLWithPath: url.path)) : .link(url)
        }
        if types.contains(.string), let s = item.string(forType: .string) {
            return classify(text: s)
        }
        return nil
    }

    /// A lone web address typed or dragged as text is still a link.
    static func classify(text: String) -> DropItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            return .link(url)
        }
        return .text(trimmed)
    }

    static func classify(_ items: [NSPasteboardItem]) -> [DropItem] {
        var seen = Set<URL>()
        return items.compactMap(classify).filter { item in
            if case .file(let url) = item { return seen.insert(url).inserted }
            return true
        }
    }
}

/// What finally reaches the agent: files to attach, and loose text (links, snippets, a selection).
struct IntakePayload: Equatable {
    var files: [URL] = []
    var text: [String] = []

    var isEmpty: Bool { files.isEmpty && text.isEmpty }

    static let defaultMessage = "Look at this."

    /// The message used when nothing can be staged and the items are sent straight away.
    var message: String {
        ([Self.defaultMessage] + text).joined(separator: "\n\n")
    }
}

/// Temp files for image data, screen grabs and text snippets, under the app's caches directory.
struct IntakeStore {
    static let maxAge: TimeInterval = 3 * 24 * 3600

    let directory: URL

    static var standard: IntakeStore {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundle = Bundle.main.bundleIdentifier ?? "Nook"
        return IntakeStore(directory: caches.appendingPathComponent(bundle).appendingPathComponent("Intake"))
    }

    /// `drop-20260919-141502-3fa9.png`: sorts by time, says where it came from, never collides in practice.
    static func name(kind: String, ext: String, date: Date = Date(),
                     token: String = String(UUID().uuidString.prefix(4)).lowercased()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let safeKind = kind.lowercased().filter { $0.isLetter || $0.isNumber }
        let safeExt = ext.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(safeKind.isEmpty ? "item" : safeKind)-\(f.string(from: date))-\(token).\(safeExt.isEmpty ? "dat" : safeExt)"
    }

    /// A fresh path; the directory exists afterwards, the file does not.
    func newURL(kind: String, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(Self.name(kind: kind, ext: ext))
    }

    func write(_ data: Data, kind: String, ext: String) throws -> URL {
        let url = try newURL(kind: kind, ext: ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Which of `files` are old enough to delete.
    static func expired(_ files: [(url: URL, modified: Date)], now: Date = Date(), maxAge: TimeInterval = maxAge) -> [URL] {
        files.filter { now.timeIntervalSince($0.modified) > maxAge }.map(\.url)
    }

    /// Run once at launch. Returns what was removed.
    @discardableResult
    func cleanUp(now: Date = Date(), maxAge: TimeInterval = IntakeStore.maxAge) -> [URL] {
        let fm = FileManager.default
        let listing = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = listing.compactMap { url -> (url: URL, modified: Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }
        let old = Self.expired(dated, now: now, maxAge: maxAge)
        old.forEach { try? fm.removeItem(at: $0) }
        return old
    }

    /// Turns classified items into a payload, writing image data to disk. TIFF becomes PNG: smaller, and every agent reads it.
    func payload(from items: [DropItem]) -> IntakePayload {
        var payload = IntakePayload()
        for item in items {
            switch item {
            case .file(let url):
                payload.files.append(url)
            case .image(var data, var ext):
                if ext != "png", let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                    data = png
                    ext = "png"
                }
                if let url = try? write(data, kind: "drop", ext: ext) { payload.files.append(url) }
            case .link(let url):
                payload.text.append(url.absoluteString)
            case .text(let text):
                payload.text.append(text)
            }
        }
        return payload
    }
}
