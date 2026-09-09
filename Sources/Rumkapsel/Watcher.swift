import CoreServices
import Foundation

/// Fires a debounced callback whenever anything under a directory tree changes.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "rumkapsel.fsevents")
    private let onChange: () -> Void
    private var pending = false
    private let debounce: TimeInterval

    init(path: String, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounce = debounce
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     0.1, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    private func fire() {
        guard !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + debounce) { [self] in
            pending = false
            onChange()
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
