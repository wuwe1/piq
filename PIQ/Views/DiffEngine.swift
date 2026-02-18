import SwiftUI

// MARK: - Diff Types

enum DiffLineType { case context, removed, added }

struct DiffDisplayLine {
    let prefix: String
    let type: DiffLineType
    let styledText: AttributedString
}

enum LineDiffOp {
    case equal(String)
    case remove(String)
    case insert(String)
}

// MARK: - Diff Computation

/// LCS-based line diff engine with character-level highlights for modified pairs.
enum DiffEngine {

    /// Returns a cached line diff result. Uses the cache stored on SessionToolCallView.
    static func cachedLineDiff(old: String, new: String) -> [DiffDisplayLine] {
        let key = NSNumber(value: "\(old)\n---\n\(new)".hashValue)
        if let cached = SessionToolCallView.diffCache.object(forKey: key) { return cached.lines }
        let result = computeLineDiff(old: old, new: new)
        SessionToolCallView.diffCache.setObject(DiffResultBox(result), forKey: key)
        return result
    }

    /// LCS-based line diff with character-level highlights for modified pairs.
    static func computeLineDiff(old: String, new: String) -> [DiffDisplayLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let ops = lcsLineDiff(oldLines, newLines)

        var result: [DiffDisplayLine] = []
        var i = 0
        while i < ops.count {
            switch ops[i] {
            case .equal(let text):
                result.append(DiffDisplayLine(
                    prefix: " ", type: .context,
                    styledText: AttributedString(text)
                ))
                i += 1
            default:
                // Gather consecutive removes/inserts as a hunk
                var removes: [String] = []
                var inserts: [String] = []
                while i < ops.count {
                    if case .remove(let t) = ops[i] { removes.append(t); i += 1 }
                    else if case .insert(let t) = ops[i] { inserts.append(t); i += 1 }
                    else { break }
                }
                // Pair up for character-level diff, interleave remove/add
                let pairs = min(removes.count, inserts.count)
                for p in 0..<pairs {
                    let (oldHL, newHL) = charHighlights(old: removes[p], new: inserts[p])
                    result.append(DiffDisplayLine(
                        prefix: "\u{2212}", type: .removed,
                        styledText: styledDiffText(removes[p], highlights: oldHL, color: .red)
                    ))
                    result.append(DiffDisplayLine(
                        prefix: "+", type: .added,
                        styledText: styledDiffText(inserts[p], highlights: newHL, color: .green)
                    ))
                }
                for p in pairs..<removes.count {
                    result.append(DiffDisplayLine(
                        prefix: "\u{2212}", type: .removed,
                        styledText: AttributedString(removes[p])
                    ))
                }
                for p in pairs..<inserts.count {
                    result.append(DiffDisplayLine(
                        prefix: "+", type: .added,
                        styledText: AttributedString(inserts[p])
                    ))
                }
            }
        }
        return result
    }

    /// LCS-based diff producing edit operations.
    static func lcsLineDiff(_ old: [String], _ new: [String]) -> [LineDiffOp] {
        let m = old.count, n = new.count
        if m == 0 { return new.map { .insert($0) } }
        if n == 0 { return old.map { .remove($0) } }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var ops: [LineDiffOp] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
                ops.append(.equal(old[i - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                ops.append(.insert(new[j - 1]))
                j -= 1
            } else {
                ops.append(.remove(old[i - 1]))
                i -= 1
            }
        }
        return ops.reversed()
    }

    /// Character-level LCS to find which chars changed between two lines.
    static func charHighlights(old: String, new: String) -> (IndexSet, IndexSet) {
        let oldChars = Array(old)
        let newChars = Array(new)
        let m = oldChars.count, n = newChars.count

        // Skip for very long lines
        if m > 500 || n > 500 { return (IndexSet(), IndexSet()) }
        if m == 0 { return (IndexSet(), n > 0 ? IndexSet(integersIn: 0..<n) : IndexSet()) }
        if n == 0 { return (m > 0 ? IndexSet(integersIn: 0..<m) : IndexSet(), IndexSet()) }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if oldChars[i - 1] == newChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find common characters
        var commonOld = Set<Int>()
        var commonNew = Set<Int>()
        var i = m, j = n
        while i > 0 && j > 0 {
            if oldChars[i - 1] == newChars[j - 1] {
                commonOld.insert(i - 1)
                commonNew.insert(j - 1)
                i -= 1; j -= 1
            } else if dp[i][j - 1] >= dp[i - 1][j] {
                j -= 1
            } else {
                i -= 1
            }
        }

        // Highlights = characters NOT in common
        var oldHL = IndexSet()
        for idx in 0..<m where !commonOld.contains(idx) { oldHL.insert(idx) }
        var newHL = IndexSet()
        for idx in 0..<n where !commonNew.contains(idx) { newHL.insert(idx) }
        return (oldHL, newHL)
    }

    /// Build AttributedString with highlighted character ranges.
    static func styledDiffText(_ text: String, highlights: IndexSet, color: Color) -> AttributedString {
        if highlights.isEmpty { return AttributedString(text) }

        var result = AttributedString()
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let isHL = highlights.contains(i)
            var j = i + 1
            while j < chars.count && highlights.contains(j) == isHL { j += 1 }

            var segment = AttributedString(String(chars[i..<j]))
            if isHL {
                segment.backgroundColor = color.opacity(0.25)
            }
            result.append(segment)
            i = j
        }
        return result
    }
}
