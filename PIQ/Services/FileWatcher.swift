import CoreServices
import Foundation

// MARK: - FileWatcher

/// Monitors directories for file changes using the FSEvents C API.
/// Detects create, modify, and delete events for `.md` files in `.claude/prds/` and `.claude/epics/`.
/// Uses a 500ms debounce to coalesce rapid changes and a 5-minute full rescan timer as fallback.
@MainActor
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private var watchedPaths: [URL] = []
    private var debounceTask: Task<Void, Never>?
    private var rescanTimer: Timer?
    private let onChange: @MainActor @Sendable () -> Void

    /// Debounce interval in nanoseconds (500ms).
    private let debounceInterval: UInt64

    /// Full rescan interval in seconds (5 minutes).
    private let rescanInterval: TimeInterval

    /// Whether the watcher is currently active.
    var isWatching: Bool { stream != nil }

    /// The paths currently being watched.
    var currentPaths: [URL] { watchedPaths }

    // MARK: - Init

    init(
        onChange: @escaping @MainActor @Sendable () -> Void,
        debounceInterval: UInt64 = 500_000_000,
        rescanInterval: TimeInterval = 300
    ) {
        self.onChange = onChange
        self.debounceInterval = debounceInterval
        self.rescanInterval = rescanInterval
    }

    // MARK: - Public API

    /// Start watching the given paths for `.md` file changes.
    /// Each path should be a project root; `.claude/` subdirectories are monitored recursively.
    func startWatching(paths: [URL]) {
        stopWatchingSync()

        let validPaths = paths.filter { url in
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
        guard !validPaths.isEmpty else { return }

        watchedPaths = validPaths
        createStream()
        startRescanTimer()
    }

    /// Stop watching all paths and clean up resources.
    func stopWatching() {
        stopWatchingSync()
    }

    /// Update the set of watched paths. Stops and restarts the stream if paths changed.
    func updatePaths(_ paths: [URL]) {
        let validPaths = paths.filter { url in
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }

        let oldSet = Set(watchedPaths.map { $0.path(percentEncoded: false) })
        let newSet = Set(validPaths.map { $0.path(percentEncoded: false) })

        guard oldSet != newSet else { return }

        if validPaths.isEmpty {
            stopWatchingSync()
        } else {
            stopWatchingSync()
            watchedPaths = validPaths
            createStream()
            startRescanTimer()
        }
    }

    // MARK: - FSEvents Stream Setup

    private func createStream() {
        // Build the list of paths to monitor: each project's .claude directory
        var monitorPaths: [String] = []
        for projectURL in watchedPaths {
            let claudeDir = projectURL.appending(path: ".claude", directoryHint: .isDirectory)
            let claudePath = claudeDir.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: claudePath) {
                monitorPaths.append(claudePath)
            } else {
                // Fall back to watching the project root
                monitorPaths.append(projectURL.path(percentEncoded: false))
            }
        }

        guard !monitorPaths.isEmpty else { return }

        let pathsCF = monitorPaths as CFArray

        // Create a context that passes a pointer to an invocation closure.
        let handler = FileWatcherCallbackHandler(onEvent: { [weak self] in
            Task { @MainActor in
                self?.handleFSEvent()
            }
        })

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(handler).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<FileWatcherCallbackHandler>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // Latency in seconds — FSEvents coalesces events within this window
            UInt32(
                kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
            )
        )

        guard let streamRef else { return }

        stream = streamRef
        FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)
        FSEventStreamStart(streamRef)
    }

    private func stopWatchingSync() {
        debounceTask?.cancel()
        debounceTask = nil

        rescanTimer?.invalidate()
        rescanTimer = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        watchedPaths = []
    }

    // MARK: - Event Handling

    /// Called from the FSEvents callback when file changes are detected.
    /// Applies debouncing: waits 500ms after the last event before triggering onChange.
    private func handleFSEvent() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.debounceInterval)
            } catch {
                return // Cancelled
            }
            self.onChange()
        }
    }

    // MARK: - Rescan Timer

    private func startRescanTimer() {
        rescanTimer?.invalidate()
        rescanTimer = Timer.scheduledTimer(
            withTimeInterval: rescanInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onChange()
            }
        }
    }
}

// MARK: - C Callback Bridge

/// A class that bridges the FSEvents C callback to Swift.
/// Must be a class so we can pass it through `Unmanaged` as a pointer.
private final class FileWatcherCallbackHandler: @unchecked Sendable {
    let onEvent: @Sendable () -> Void

    init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }
}

/// The C function pointer callback for FSEvents.
/// Receives events and filters for `.md` file changes in `.claude/prds/` or `.claude/epics/`.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }

    // Check if any event involves a relevant .md file
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var hasRelevantChange = false

    for i in 0..<numEvents {
        guard let pathCF = CFArrayGetValueAtIndex(paths, i) else { continue }
        let path = Unmanaged<CFString>.fromOpaque(pathCF).takeUnretainedValue() as String

        if isRelevantPath(path) {
            hasRelevantChange = true
            break
        }
    }

    guard hasRelevantChange else { return }

    let handler = Unmanaged<FileWatcherCallbackHandler>.fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    handler.onEvent()
}

/// Check if a file path is a `.md` file inside `.claude/prds/` or `.claude/epics/`.
private func isRelevantPath(_ path: String) -> Bool {
    guard path.hasSuffix(".md") else { return false }
    return path.contains("/.claude/prds/") || path.contains("/.claude/epics/")
}
