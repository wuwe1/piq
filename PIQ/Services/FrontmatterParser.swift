import Foundation

// MARK: - FrontmatterValue

enum FrontmatterValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([String])

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var arrayValue: [String]? {
        if case .array(let v) = self { return v }
        return nil
    }
}

// MARK: - ParsedItem

enum ParsedItem: Sendable {
    case prd(PRDItem)
    case epic(EpicItem)
    case task(TaskItem)
}

// MARK: - FrontmatterParser

enum FrontmatterParser {
    /// Parse YAML frontmatter from markdown content into key-value pairs.
    static func parse(_ content: String) -> [String: FrontmatterValue]? {
        let lines = content.components(separatedBy: .newlines)
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex, end > 1 else {
            return nil
        }

        let yamlLines = Array(lines[1..<end])
        return parseYAMLLines(yamlLines)
    }

    /// Parse a markdown file at the given URL and return a typed item.
    static func parseFile(at url: URL, as type: ItemType) -> ParsedItem? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        guard let frontmatter = parse(content) else {
            return nil
        }

        switch type {
        case .prd:
            return parsePRD(frontmatter: frontmatter, filePath: url)
        case .epic:
            return parseEpic(frontmatter: frontmatter, filePath: url)
        case .task:
            return parseTask(frontmatter: frontmatter, filePath: url)
        }
    }

    // MARK: - Private helpers

    private static func parseYAMLLines(_ lines: [String]) -> [String: FrontmatterValue] {
        var result: [String: FrontmatterValue] = [:]
        var currentKey: String?
        var currentArray: [String] = []

        for line in lines {
            // Array continuation line
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                if let key = currentKey {
                    let value = line.trimmingCharacters(in: .whitespaces)
                        .dropFirst(2)
                        .trimmingCharacters(in: .whitespaces)
                    currentArray.append(unquote(String(value)))
                    result[key] = .array(currentArray)
                }
                continue
            }

            // Flush any in-progress array
            currentKey = nil
            currentArray = []

            // Split only at the first colon
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            let rawValue = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

            if rawValue.isEmpty {
                // Possible start of an array
                currentKey = key
                currentArray = []
                continue
            }

            result[key] = inferValue(rawValue)
        }

        return result
    }

    private static func inferValue(_ raw: String) -> FrontmatterValue {
        // Boolean
        let lower = raw.lowercased()
        if lower == "true" { return .bool(true) }
        if lower == "false" { return .bool(false) }

        // Integer (pure digits, possibly negative)
        if let intVal = Int(raw) {
            return .int(intVal)
        }

        // Inline array: [a, b, c]
        if raw.hasPrefix("[") && raw.hasSuffix("]") {
            let inner = raw.dropFirst().dropLast()
            let items = inner.split(separator: ",").map {
                unquote($0.trimmingCharacters(in: .whitespaces))
            }
            return .array(items)
        }

        // Quoted string — remove quotes
        return .string(unquote(raw))
    }

    private static func unquote(_ s: String) -> String {
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) ||
           (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    // MARK: - Item construction

    private static func parsePRD(frontmatter fm: [String: FrontmatterValue], filePath: URL) -> ParsedItem? {
        guard let name = fm["name"]?.stringValue else { return nil }

        let status = fm["status"]?.stringValue.flatMap { ItemStatus(tolerant: $0) } ?? .backlog
        let description = fm["description"]?.stringValue ?? ""
        let created = parseDate(fm["created"])
        let updated = parseDate(fm["updated"])

        return .prd(PRDItem(
            name: name,
            description: description,
            status: status,
            filePath: filePath,
            created: created,
            updated: updated
        ))
    }

    private static func parseEpic(frontmatter fm: [String: FrontmatterValue], filePath: URL) -> ParsedItem? {
        guard let name = fm["name"]?.stringValue else { return nil }

        let status = fm["status"]?.stringValue.flatMap { ItemStatus(tolerant: $0) } ?? .backlog
        let description = fm["description"]?.stringValue ?? ""
        let progress = fm["progress"]?.intValue ?? parseProgressString(fm["progress"])
        let created = parseDate(fm["created"])
        let updated = parseDate(fm["updated"])

        let github = fm["github"]?.stringValue.flatMap { str in
            str.isEmpty ? nil : URL(string: str)
        }

        return .epic(EpicItem(
            name: name,
            description: description,
            status: status,
            filePath: filePath,
            created: created,
            updated: updated,
            progress: progress,
            github: github
        ))
    }

    private static func parseTask(frontmatter fm: [String: FrontmatterValue], filePath: URL) -> ParsedItem? {
        guard let name = fm["name"]?.stringValue else { return nil }

        let status = fm["status"]?.stringValue.flatMap { ItemStatus(tolerant: $0) } ?? .open
        let description = fm["description"]?.stringValue ?? ""
        let created = parseDate(fm["created"])
        let updated = parseDate(fm["updated"])
        let taskID = filePath.deletingPathExtension().lastPathComponent

        let github = fm["github"]?.stringValue.flatMap { str in
            str.isEmpty ? nil : URL(string: str)
        }

        return .task(TaskItem(
            taskID: taskID,
            name: name,
            description: description,
            status: status,
            filePath: filePath,
            github: github,
            created: created,
            updated: updated
        ))
    }

    // MARK: - Date parsing

    private static func parseDate(_ value: FrontmatterValue?) -> Date {
        guard let raw = value?.stringValue else { return Date() }
        if let date = try? Date(raw, strategy: .iso8601) {
            return date
        }
        // Fallback for date-only format "YYYY-MM-DD"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw) ?? Date()
    }

    /// Parse progress from string like "75%" or "75".
    private static func parseProgressString(_ value: FrontmatterValue?) -> Int {
        guard let raw = value?.stringValue else { return 0 }
        let cleaned = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Int(cleaned) ?? 0
    }
}
