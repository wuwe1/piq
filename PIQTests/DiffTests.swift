import XCTest
@testable import PIQ

// NOTE: The diff types and functions have been extracted to DiffEngine (PIQ/Views/DiffEngine.swift).
// Types (now top-level):
//   - DiffLineType
//   - DiffDisplayLine
//   - LineDiffOp
//
// Functions (on DiffEngine enum):
//   - DiffEngine.computeLineDiff
//   - DiffEngine.lcsLineDiff
//   - DiffEngine.charHighlights
//   - DiffEngine.styledDiffText

final class DiffTests: XCTestCase {

    // MARK: - lcsLineDiff: Basic Operations

    func testLcsLineDiff_identicalLines() {
        let old = ["alpha", "beta", "gamma"]
        let new = ["alpha", "beta", "gamma"]

        let ops = DiffEngine.lcsLineDiff(old, new)

        XCTAssertEqual(ops.count, 3)
        for op in ops {
            guard case .equal = op else {
                XCTFail("All ops should be .equal for identical input")
                return
            }
        }
    }

    func testLcsLineDiff_allRemoved() {
        let old = ["line1", "line2"]
        let new: [String] = []

        let ops = DiffEngine.lcsLineDiff(old, new)

        XCTAssertEqual(ops.count, 2)
        for op in ops {
            guard case .remove = op else {
                XCTFail("All ops should be .remove when new is empty")
                return
            }
        }
    }

    func testLcsLineDiff_allInserted() {
        let old: [String] = []
        let new = ["line1", "line2"]

        let ops = DiffEngine.lcsLineDiff(old, new)

        XCTAssertEqual(ops.count, 2)
        for op in ops {
            guard case .insert = op else {
                XCTFail("All ops should be .insert when old is empty")
                return
            }
        }
    }

    func testLcsLineDiff_singleLineModification() {
        let old = ["hello world"]
        let new = ["hello swift"]

        let ops = DiffEngine.lcsLineDiff(old, new)

        // Since the lines differ, we expect a remove + insert
        XCTAssertEqual(ops.count, 2)
        if case .remove(let text) = ops[0] {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("First op should be .remove")
        }
        if case .insert(let text) = ops[1] {
            XCTAssertEqual(text, "hello swift")
        } else {
            XCTFail("Second op should be .insert")
        }
    }

    func testLcsLineDiff_additionInMiddle() {
        let old = ["first", "third"]
        let new = ["first", "second", "third"]

        let ops = DiffEngine.lcsLineDiff(old, new)

        // Should be: equal("first"), insert("second"), equal("third")
        XCTAssertEqual(ops.count, 3)
        if case .equal(let t) = ops[0] { XCTAssertEqual(t, "first") }
        else { XCTFail("Expected .equal") }
        if case .insert(let t) = ops[1] { XCTAssertEqual(t, "second") }
        else { XCTFail("Expected .insert") }
        if case .equal(let t) = ops[2] { XCTAssertEqual(t, "third") }
        else { XCTFail("Expected .equal") }
    }

    func testLcsLineDiff_deletionInMiddle() {
        let old = ["first", "second", "third"]
        let new = ["first", "third"]

        let ops = DiffEngine.lcsLineDiff(old, new)

        XCTAssertEqual(ops.count, 3)
        if case .equal(let t) = ops[0] { XCTAssertEqual(t, "first") }
        else { XCTFail("Expected .equal") }
        if case .remove(let t) = ops[1] { XCTAssertEqual(t, "second") }
        else { XCTFail("Expected .remove") }
        if case .equal(let t) = ops[2] { XCTAssertEqual(t, "third") }
        else { XCTFail("Expected .equal") }
    }

    func testLcsLineDiff_bothEmpty() {
        let ops = DiffEngine.lcsLineDiff([], [])

        XCTAssertTrue(ops.isEmpty)
    }

    func testLcsLineDiff_completelyDifferent() {
        let old = ["aaa", "bbb"]
        let new = ["ccc", "ddd"]

        let ops = DiffEngine.lcsLineDiff(old, new)

        // No common lines, so all removes then all inserts (order depends on LCS backtrack)
        let removes = ops.filter { if case .remove = $0 { return true }; return false }
        let inserts = ops.filter { if case .insert = $0 { return true }; return false }
        XCTAssertEqual(removes.count, 2)
        XCTAssertEqual(inserts.count, 2)
    }

    // MARK: - computeLineDiff: Line-Level Display

    func testComputeLineDiff_identicalStrings() {
        let text = "line1\nline2\nline3"
        let lines = DiffEngine.computeLineDiff(old: text, new: text)

        XCTAssertEqual(lines.count, 3)
        for line in lines {
            XCTAssertEqual(line.type, .context, "Identical lines should be context type")
            XCTAssertEqual(line.prefix, " ")
        }
    }

    func testComputeLineDiff_emptyStrings() {
        let lines = DiffEngine.computeLineDiff(old: "", new: "")

        // Empty string splits into [""], so we get one context line
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].type, .context)
    }

    func testComputeLineDiff_addedLines() {
        let old = ""
        let new = "new line 1\nnew line 2"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        // old splits into [""], new splits into ["new line 1", "new line 2"]
        // The empty string in old doesn't match anything, so we get removes and inserts
        let addedLines = lines.filter { $0.type == .added }
        XCTAssertGreaterThan(addedLines.count, 0, "Should have added lines")
        for line in addedLines {
            XCTAssertEqual(line.prefix, "+")
        }
    }

    func testComputeLineDiff_removedLines() {
        let old = "old line 1\nold line 2"
        let new = ""

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        let removedLines = lines.filter { $0.type == .removed }
        XCTAssertGreaterThan(removedLines.count, 0, "Should have removed lines")
        for line in removedLines {
            XCTAssertEqual(line.prefix, "\u{2212}") // minus sign
        }
    }

    func testComputeLineDiff_modifiedLine() {
        let old = "let x = 1"
        let new = "let x = 2"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        // Should produce a remove/add pair with character-level highlighting
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].type, .removed)
        XCTAssertEqual(lines[1].type, .added)
    }

    func testComputeLineDiff_mixedChanges() {
        let old = "keep this\nremove this\nkeep this too"
        let new = "keep this\nadd this\nkeep this too"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        // Should have: context, remove, add, context
        let contextLines = lines.filter { $0.type == .context }
        let removedLines = lines.filter { $0.type == .removed }
        let addedLines = lines.filter { $0.type == .added }

        XCTAssertEqual(contextLines.count, 2, "Two unchanged lines")
        XCTAssertEqual(removedLines.count, 1, "One removed line")
        XCTAssertEqual(addedLines.count, 1, "One added line")
    }

    func testComputeLineDiff_multipleHunks() {
        let old = "a\nb\nc\nd\ne"
        let new = "a\nB\nc\nD\ne"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        let contextLines = lines.filter { $0.type == .context }
        let removedLines = lines.filter { $0.type == .removed }
        let addedLines = lines.filter { $0.type == .added }

        XCTAssertEqual(contextLines.count, 3, "Lines a, c, e are unchanged")
        XCTAssertEqual(removedLines.count, 2, "Lines b and d are removed")
        XCTAssertEqual(addedLines.count, 2, "Lines B and D are added")
    }

    // MARK: - charHighlights: Character-Level Diff

    func testCharHighlights_identicalStrings() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "hello", new: "hello")

        XCTAssertTrue(oldHL.isEmpty, "No highlights for identical strings")
        XCTAssertTrue(newHL.isEmpty, "No highlights for identical strings")
    }

    func testCharHighlights_completelyDifferent() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "abc", new: "xyz")

        XCTAssertEqual(oldHL.count, 3, "All old chars should be highlighted")
        XCTAssertEqual(newHL.count, 3, "All new chars should be highlighted")
    }

    func testCharHighlights_singleCharChange() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "cat", new: "bat")

        // 'c' changed to 'b', 'a' and 't' are common
        XCTAssertEqual(oldHL.count, 1, "Only 'c' should be highlighted in old")
        XCTAssertTrue(oldHL.contains(0), "Index 0 ('c') should be highlighted")
        XCTAssertEqual(newHL.count, 1, "Only 'b' should be highlighted in new")
        XCTAssertTrue(newHL.contains(0), "Index 0 ('b') should be highlighted")
    }

    func testCharHighlights_emptyOld() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "", new: "abc")

        XCTAssertTrue(oldHL.isEmpty, "Empty old should have no highlights")
        XCTAssertEqual(newHL.count, 3, "All new chars should be highlighted")
        XCTAssertTrue(newHL.contains(0))
        XCTAssertTrue(newHL.contains(1))
        XCTAssertTrue(newHL.contains(2))
    }

    func testCharHighlights_emptyNew() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "abc", new: "")

        XCTAssertEqual(oldHL.count, 3, "All old chars should be highlighted")
        XCTAssertTrue(newHL.isEmpty, "Empty new should have no highlights")
    }

    func testCharHighlights_bothEmpty() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "", new: "")

        XCTAssertTrue(oldHL.isEmpty)
        XCTAssertTrue(newHL.isEmpty)
    }

    func testCharHighlights_additionAtEnd() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "hello", new: "hello world")

        XCTAssertTrue(oldHL.isEmpty, "No chars removed from old")
        XCTAssertEqual(newHL.count, 6, "' world' (6 chars) should be highlighted in new")
    }

    func testCharHighlights_insertionInMiddle() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "ac", new: "abc")

        // 'a' and 'c' are common; 'b' is inserted
        XCTAssertTrue(oldHL.isEmpty, "No chars removed from old")
        XCTAssertEqual(newHL.count, 1, "Only 'b' should be highlighted")
        XCTAssertTrue(newHL.contains(1), "Index 1 ('b') should be highlighted")
    }

    func testCharHighlights_deletionFromMiddle() {
        let (oldHL, newHL) = DiffEngine.charHighlights(old: "abc", new: "ac")

        XCTAssertEqual(oldHL.count, 1, "Only 'b' should be highlighted in old")
        XCTAssertTrue(oldHL.contains(1), "Index 1 ('b') should be highlighted")
        XCTAssertTrue(newHL.isEmpty, "No chars added in new")
    }

    func testCharHighlights_skipsVeryLongLines() {
        let longOld = String(repeating: "a", count: 501)
        let longNew = String(repeating: "b", count: 501)

        let (oldHL, newHL) = DiffEngine.charHighlights(old: longOld, new: longNew)

        XCTAssertTrue(oldHL.isEmpty, "Should return empty for lines > 500 chars")
        XCTAssertTrue(newHL.isEmpty, "Should return empty for lines > 500 chars")
    }

    func testCharHighlights_exactlyAtLimit() {
        let old500 = String(repeating: "a", count: 500)
        let new500 = String(repeating: "b", count: 500)

        let (oldHL, newHL) = DiffEngine.charHighlights(old: old500, new: new500)

        // 500 chars is at the limit, should still compute (not > 500)
        XCTAssertEqual(oldHL.count, 500, "Should highlight all chars at exactly 500")
        XCTAssertEqual(newHL.count, 500, "Should highlight all chars at exactly 500")
    }

    // MARK: - computeLineDiff: Integration with Character Highlights

    func testComputeLineDiff_singleCharChangeProducesCharHighlights() {
        let old = "let value = 42"
        let new = "let value = 43"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        XCTAssertEqual(lines.count, 2)
        // The styledText should be an AttributedString (we can verify it's non-empty)
        XCTAssertFalse(lines[0].styledText.characters.isEmpty)
        XCTAssertFalse(lines[1].styledText.characters.isEmpty)
    }

    func testComputeLineDiff_preservesLineOrder() {
        let old = "first\nsecond\nthird"
        let new = "first\nmodified\nthird"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        // Expected: context(first), removed(second), added(modified), context(third)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].type, .context)
        XCTAssertEqual(lines[1].type, .removed)
        XCTAssertEqual(lines[2].type, .added)
        XCTAssertEqual(lines[3].type, .context)
    }

    func testComputeLineDiff_unpairableRemovesAndInserts() {
        // More removes than inserts -- the extras should not be paired for char highlights
        let old = "aaa\nbbb\nccc"
        let new = "zzz"

        let lines = DiffEngine.computeLineDiff(old: old, new: new)

        let removedCount = lines.filter { $0.type == .removed }.count
        let addedCount = lines.filter { $0.type == .added }.count

        XCTAssertGreaterThanOrEqual(removedCount, 2, "Should have multiple removed lines")
        XCTAssertGreaterThanOrEqual(addedCount, 1, "Should have at least one added line")
    }

    // MARK: - styledDiffText

    func testStyledDiffText_noHighlights() {
        let result = DiffEngine.styledDiffText("hello", highlights: IndexSet(), color: .red)

        XCTAssertEqual(String(result.characters), "hello")
    }

    func testStyledDiffText_allHighlighted() {
        let highlights = IndexSet(integersIn: 0..<5)
        let result = DiffEngine.styledDiffText("hello", highlights: highlights, color: .green)

        XCTAssertEqual(String(result.characters), "hello")
        // The background color should be applied (we verify the text is correct;
        // full AttributedString color verification requires deeper introspection)
    }

    func testStyledDiffText_partialHighlights() {
        var highlights = IndexSet()
        highlights.insert(2)  // 'l'
        highlights.insert(3)  // 'l'
        let result = DiffEngine.styledDiffText("hello", highlights: highlights, color: .red)

        XCTAssertEqual(String(result.characters), "hello", "Text content should be preserved")
    }
}
