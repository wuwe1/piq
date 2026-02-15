import CoreServices
import Foundation

// MARK: - SessionFileWatcher

/// Monitors ~/.claude/projects/ recursively for JSONL file changes using FSEvents.
@MainActor
final class SessionFileWatcher {
    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private let onChange: @MainActor @Sendable () -> Void

    /// Debounce interval: 1 second (session files update frequently).
    private let debounceNanos: UInt64 = 1_000_000_000

    var isWatching: Bool { stream != nil }

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    // MARK: - Public API

    func startWatching() {
        stopWatching()
        createStream()
    }

    func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    // MARK: - FSEvents Stream

    private func createStream() {
        let rootPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects")
            .path(percentEncoded: false)

        guard FileManager.default.fileExists(atPath: rootPath) else { return }

        let paths = [rootPath] as CFArray

        let handler = SessionWatcherCallbackHandler { [weak self] in
            Task { @MainActor in
                self?.handleEvent()
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(handler).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<SessionWatcherCallbackHandler>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            sessionFSEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
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

    private func handleEvent() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.debounceNanos)
            } catch {
                return
            }
            self.onChange()
        }
    }
}

// MARK: - C Callback Bridge

private final class SessionWatcherCallbackHandler: @unchecked Sendable {
    let onEvent: @Sendable () -> Void
    init(onEvent: @escaping @Sendable () -> Void) { self.onEvent = onEvent }
}

private func sessionFSEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var hasRelevantChange = false

    for i in 0..<numEvents {
        guard let pathCF = CFArrayGetValueAtIndex(paths, i) else { continue }
        let path = Unmanaged<CFString>.fromOpaque(pathCF).takeUnretainedValue() as String

        if path.hasSuffix(".jsonl") {
            hasRelevantChange = true
            break
        }
    }

    guard hasRelevantChange else { return }

    let handler = Unmanaged<SessionWatcherCallbackHandler>.fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    handler.onEvent()
}
