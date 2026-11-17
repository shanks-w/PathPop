import Foundation

/// A deterministic parser. The caller supplies the home directory and existence check;
/// this type never reads the clipboard, opens files, or changes application state.
enum PathExtractor {
    enum Failure: Error, Equatable {
        case emptyText
        case noPathFound
        case pathsDoNotExist([String])
        case confirmationRequired([String])
    }

    static func extract(
        from text: String,
        homeDirectory: String,
        fileExists: (String) -> Bool
    ) -> Result<URL, Failure> {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.emptyText) }

        var attempted: [String] = []
        var seen = Set<String>()

        func existingURL(_ variant: String) -> URL? {
            guard let url = localURL(from: variant, homeDirectory: homeDirectory),
                  seen.insert(url.path).inserted else { return nil }
            attempted.append(url.path)
            return fileExists(url.path) ? url : nil
        }

        // Only literal paths and explicit wrappers/escaped spaces may reveal directly.
        let exactVariants = variants(of: text, stripLineSuffix: false, stripPunctuation: false)
        for variant in exactVariants {
            if let url = existingURL(variant) { return .success(url) }
        }
        let isSinglePath = exactVariants.contains { localURL(from: $0, homeDirectory: homeDirectory) != nil }
            && pathStart.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) <= 1
        var inferred: [String] = []
        if isSinglePath {
            // Never shorten a missing filename at spaces or punctuation. Numeric
            // suffixes may be line numbers OR real filename characters: ask first.
            for variant in variants(of: text, stripPunctuation: false) {
                if let url = existingURL(variant) { inferred.append(url.path) }
            }
        } else {
            for candidate in [text] + embeddedCandidates(in: text) {
                for variant in variants(of: candidate) {
                    if let url = existingURL(variant) { inferred.append(url.path) }
                }
            }
        }
        if !inferred.isEmpty { return .failure(.confirmationRequired(inferred)) }
        return .failure(attempted.isEmpty ? .noPathFound : .pathsDoNotExist(attempted))
    }

    private static let pathStart = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_/\\:~])(?:file://|~/|/)"#,
        options: [.caseInsensitive]
    )
    private static let lineSuffix = try! NSRegularExpression(pattern: #"(?::[0-9]+){1,2}$"#)
    private static let wrappers: [(String, String)] = [
        ("\"", "\""), ("'", "'"), ("`", "`"), ("“", "”"), ("‘", "’"),
        ("(", ")"), ("[", "]"), ("{", "}"), ("<", ">"), ("（", "）"),
        ("【", "】"), ("《", "》"), ("「", "」")
    ]
    private static let trailingDelimiters = Set(".,;:!?，。；：！？\"'`”’)]}>）】》」")

    private static func variants(of raw: String, stripLineSuffix: Bool = true, stripPunctuation: Bool = true) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func add(_ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, seen.insert(value).inserted { result.append(value) }
        }
        add(raw)
        var index = 0
        while index < result.count {
            let value = result[index]
            index += 1
            for (left, right) in wrappers where value.hasPrefix(left) && value.hasSuffix(right) {
                if value.count >= left.count + right.count {
                    add(String(value.dropFirst(left.count).dropLast(right.count)))
                }
            }
            let range = NSRange(value.startIndex..., in: value)
            if stripLineSuffix, let match = lineSuffix.firstMatch(in: value, range: range),
               let suffixRange = Range(match.range, in: value) {
                add(String(value[..<suffixRange.lowerBound]))
            }
            // Keep the literal spelling first: a backslash or terminal punctuation
            // can also be a real filename character on macOS.
            if value.contains("\\ ") { add(value.replacingOccurrences(of: "\\ ", with: " ")) }
            if stripPunctuation, let last = value.last, trailingDelimiters.contains(last),
               !(last == "?" && value.lowercased().hasPrefix("file://")) {
                add(String(value.dropLast()))
            }
        }
        return result
    }

    private static func localURL(from value: String, homeDirectory: String) -> URL? {
        let path: String
        if value.lowercased().hasPrefix("file://") {
            // Encode raw Unicode while preserving existing %HH escapes. Letting
            // URL auto-encode a mixed Unicode/escaped input can double-encode %20.
            let urlCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: urlCharacters),
                  let url = URL(string: encoded, encodingInvalidCharacters: false), url.isFileURL,
                  url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
                  url.query == nil, url.fragment == nil else { return nil }
            path = url.path(percentEncoded: false)
        } else if value.hasPrefix("~/") {
            path = homeDirectory + String(value.dropFirst())
        } else if value.hasPrefix("/") {
            path = value
        } else {
            return nil
        }
        guard path.hasPrefix("/"), !path.contains("\0"), !path.contains("\n"), !path.contains("\r") else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func embeddedCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()
        func add(_ value: Substring) {
            let value = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, seen.insert(value).inserted { candidates.append(value) }
        }
        for match in pathStart.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let tail = text[range.lowerBound...].prefix { !$0.isNewline }
            let isFileURL = tail.lowercased().hasPrefix("file://")
            add(tail)
            for index in tail.indices {
                let character = tail[index]
                if character.isWhitespace {
                    // A shell-escaped space belongs to the filename.
                    let precedingBackslashes = tail[..<index].reversed().prefix { $0 == "\\" }.count
                    if precedingBackslashes % 2 == 0 { add(tail[..<index]) }
                } else if trailingDelimiters.contains(character),
                          !(character == "?" && isFileURL) {
                    add(tail[...index])
                }
            }
        }
        // Longest first, with original text order as the tie breaker.
        return candidates.enumerated().sorted {
            $0.element.count == $1.element.count
                ? $0.offset < $1.offset
                : $0.element.count > $1.element.count
        }.map(\.element)
    }
}
