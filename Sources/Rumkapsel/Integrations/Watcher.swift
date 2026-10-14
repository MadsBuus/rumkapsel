import CoreServices
import Foundation

final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "rumkapsel.fsevents")
    private let onChange: ([String]) -> Void
    private var pending: [String] = []
    private let debounce: TimeInterval

    init(path: String, excluding: [String] = [], debounce: TimeInterval = 0.15, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        self.debounce = debounce
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]) ?? []
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().fire(Array(list.prefix(count)))
        }
        let flags = kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     0.1, FSEventStreamCreateFlags(flags))
        if let stream {
            if !excluding.isEmpty { FSEventStreamSetExclusionPaths(stream, excluding as CFArray) }
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    private func fire(_ paths: [String]) {
        let first = pending.isEmpty
        pending += paths.isEmpty ? [""] : paths
        guard first else { return }
        queue.asyncAfter(deadline: .now() + debounce) { [self] in
            let all = pending
            pending = []
            onChange(all)
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
