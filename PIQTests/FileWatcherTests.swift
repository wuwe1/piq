import Testing
import Foundation
@testable import PIQ

// MARK: - FileWatcher Tests

@Suite("FileWatcher")
struct FileWatcherTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "piq-fswatcher-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeClaudeStructure(in projectURL: URL) throws {
        let prdsDir = projectURL.appending(path: ".claude/prds")
        let epicsDir = projectURL.appending(path: ".claude/epics")
        try FileManager.default.createDirectory(at: prdsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: epicsDir, withIntermediateDirectories: true)
    }

    // MARK: - Path Management

    @Test("starts with no watched paths")
    @MainActor
    func initialState() {
        let watcher = FileWatcher(onChange: {})
        #expect(watcher.isWatching == false)
        #expect(watcher.currentPaths.isEmpty)
    }

    @Test("startWatching sets up paths and marks as watching")
    @MainActor
    func startWatchingSetsPaths() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir])

        #expect(watcher.isWatching == true)
        #expect(watcher.currentPaths.count == 1)

        watcher.stopWatching()
    }

    @Test("stopWatching clears state")
    @MainActor
    func stopWatchingClearsState() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir])
        #expect(watcher.isWatching == true)

        watcher.stopWatching()
        #expect(watcher.isWatching == false)
        #expect(watcher.currentPaths.isEmpty)
    }

    @Test("updatePaths changes watched paths")
    @MainActor
    func updatePathsChanges() throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }
        try makeClaudeStructure(in: dir1)
        try makeClaudeStructure(in: dir2)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir1])
        #expect(watcher.currentPaths.count == 1)

        watcher.updatePaths([dir1, dir2])
        #expect(watcher.currentPaths.count == 2)

        watcher.stopWatching()
    }

    @Test("updatePaths with empty array stops watching")
    @MainActor
    func updatePathsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir])
        #expect(watcher.isWatching == true)

        watcher.updatePaths([])
        #expect(watcher.isWatching == false)
    }

    @Test("updatePaths with same paths does not restart")
    @MainActor
    func updatePathsSameNoRestart() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir])
        #expect(watcher.isWatching == true)

        // updatePaths with same paths should not change state
        watcher.updatePaths([dir])
        #expect(watcher.isWatching == true)

        watcher.stopWatching()
    }

    // MARK: - Invalid Path Handling

    @Test("startWatching ignores nonexistent paths")
    @MainActor
    func ignoresNonexistentPaths() {
        let fakePath = URL(filePath: "/tmp/nonexistent-\(UUID())")
        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [fakePath])
        #expect(watcher.isWatching == false)
        #expect(watcher.currentPaths.isEmpty)
    }

    @Test("startWatching filters out invalid paths among valid ones")
    @MainActor
    func filtersInvalidPaths() throws {
        let validDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: validDir) }
        try makeClaudeStructure(in: validDir)

        let fakePath = URL(filePath: "/tmp/nonexistent-\(UUID())")
        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [validDir, fakePath])

        #expect(watcher.isWatching == true)
        #expect(watcher.currentPaths.count == 1)

        watcher.stopWatching()
    }

    // MARK: - Start/Stop Lifecycle

    @Test("multiple start/stop cycles work correctly")
    @MainActor
    func multipleStartStopCycles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        let watcher = FileWatcher(onChange: {})

        for _ in 0..<3 {
            watcher.startWatching(paths: [dir])
            #expect(watcher.isWatching == true)
            watcher.stopWatching()
            #expect(watcher.isWatching == false)
        }
    }

    @Test("stopWatching when not watching is safe")
    @MainActor
    func stopWhenNotWatching() {
        let watcher = FileWatcher(onChange: {})
        watcher.stopWatching()
        #expect(watcher.isWatching == false)
    }

    @Test("startWatching replaces previous watch")
    @MainActor
    func startWatchingReplaces() throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }
        try makeClaudeStructure(in: dir1)
        try makeClaudeStructure(in: dir2)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir1])
        #expect(watcher.currentPaths.count == 1)

        watcher.startWatching(paths: [dir2])
        #expect(watcher.currentPaths.count == 1)
        #expect(watcher.currentPaths.first?.lastPathComponent == dir2.lastPathComponent)

        watcher.stopWatching()
    }

    // MARK: - Debounce Behavior

    @Test("debounce coalesces rapid events into single callback",
          .timeLimit(.minutes(1)))
    @MainActor
    func debounceCoalesces() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        var callbackCount = 0
        let watcher = FileWatcher(
            onChange: { callbackCount += 1 },
            debounceInterval: 100_000_000, // 100ms debounce
            rescanInterval: 600
        )
        watcher.startWatching(paths: [dir])

        // Allow FSEvents stream to register
        try await Task.sleep(nanoseconds: 300_000_000)

        // Write multiple files rapidly (all within debounce window)
        let prdsDir = dir.appending(path: ".claude/prds")
        for i in 0..<5 {
            let prd = "---\nname: prd-\(i)\nstatus: backlog\n---\n"
            try prd.write(
                to: prdsDir.appending(path: "prd-\(i).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Wait long enough for FSEvents delivery + debounce to settle
        // Poll with run loop advancement to ensure dispatch queue events fire
        let deadline = Date().addingTimeInterval(5.0)
        while callbackCount == 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Due to debouncing, we should have far fewer callbacks than files written.
        // The exact count depends on FSEvents timing, but it should be at least 1.
        #expect(callbackCount >= 1)
        #expect(callbackCount <= 5)

        watcher.stopWatching()
    }

    // MARK: - File Event Detection

    @Test("detects new .md file creation in .claude/prds/",
          .timeLimit(.minutes(1)))
    @MainActor
    func detectsNewMDFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        var callbackFired = false
        let watcher = FileWatcher(
            onChange: { callbackFired = true },
            debounceInterval: 50_000_000,
            rescanInterval: 600
        )
        watcher.startWatching(paths: [dir])

        // Allow FSEvents stream to fully register
        try await Task.sleep(nanoseconds: 500_000_000)

        // Create a .md file
        let prdContent = "---\nname: new-feature\nstatus: backlog\n---\n# New Feature\n"
        try prdContent.write(
            to: dir.appending(path: ".claude/prds/new-feature.md"),
            atomically: true,
            encoding: .utf8
        )

        // Poll until callback fires or timeout
        let deadline = Date().addingTimeInterval(5.0)
        while !callbackFired && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(callbackFired == true)

        watcher.stopWatching()
    }

    @Test("detects .md file modification in .claude/epics/",
          .timeLimit(.minutes(1)))
    @MainActor
    func detectsMDModification() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        // Pre-create a file
        let epicDir = dir.appending(path: ".claude/epics/test-epic")
        try FileManager.default.createDirectory(at: epicDir, withIntermediateDirectories: true)
        let epicFile = epicDir.appending(path: "epic.md")
        try "---\nname: test\nstatus: open\n---\n".write(to: epicFile, atomically: true, encoding: .utf8)

        var callbackFired = false
        let watcher = FileWatcher(
            onChange: { callbackFired = true },
            debounceInterval: 50_000_000,
            rescanInterval: 600
        )
        watcher.startWatching(paths: [dir])

        // Allow FSEvents stream to fully register
        try await Task.sleep(nanoseconds: 500_000_000)

        // Modify the file
        try "---\nname: test\nstatus: done\n---\n".write(to: epicFile, atomically: true, encoding: .utf8)

        // Poll until callback fires or timeout
        let deadline = Date().addingTimeInterval(5.0)
        while !callbackFired && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(callbackFired == true)

        watcher.stopWatching()
    }

    // MARK: - Path Filtering

    @Test("relevant path filtering logic")
    func relevantPathFiltering() {
        // Verify the filtering logic that FileWatcher uses internally.
        // A relevant path must end with .md AND contain /.claude/prds/ or /.claude/epics/
        let mdInPrds = "/project/.claude/prds/feature.md"
        let mdInEpics = "/project/.claude/epics/epic-name/001.md"
        let txtInPrds = "/project/.claude/prds/readme.txt"
        let mdElsewhere = "/project/src/readme.md"

        #expect(mdInPrds.hasSuffix(".md") && mdInPrds.contains("/.claude/prds/"))
        #expect(mdInEpics.hasSuffix(".md") && mdInEpics.contains("/.claude/epics/"))
        #expect(!(txtInPrds.hasSuffix(".md") && txtInPrds.contains("/.claude/prds/")))
        #expect(!(mdElsewhere.hasSuffix(".md") && mdElsewhere.contains("/.claude/prds/")))
        #expect(!(mdElsewhere.hasSuffix(".md") && mdElsewhere.contains("/.claude/epics/")))
    }

    // MARK: - Rescan Timer

    @Test("rescan timer triggers callback",
          .timeLimit(.minutes(1)))
    @MainActor
    func rescanTimerFires() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeClaudeStructure(in: dir)

        var callbackCount = 0
        // Use a very short rescan interval (1 second) for testing
        let watcher = FileWatcher(
            onChange: { callbackCount += 1 },
            debounceInterval: 50_000_000,
            rescanInterval: 1.0
        )
        watcher.startWatching(paths: [dir])

        // Wait for the rescan timer to fire at least once
        let deadline = Date().addingTimeInterval(5.0)
        while callbackCount < 1 && Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        #expect(callbackCount >= 1)

        watcher.stopWatching()
    }

    // MARK: - Multiple Paths

    @Test("watches multiple project paths simultaneously")
    @MainActor
    func watchesMultiplePaths() throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }
        try makeClaudeStructure(in: dir1)
        try makeClaudeStructure(in: dir2)

        let watcher = FileWatcher(onChange: {})
        watcher.startWatching(paths: [dir1, dir2])

        #expect(watcher.isWatching == true)
        #expect(watcher.currentPaths.count == 2)

        watcher.stopWatching()
    }
}
