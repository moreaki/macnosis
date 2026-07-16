import Foundation

struct AppBundleDiscovery: Sendable {
    private let batchSize: Int

    init(batchSize: Int = 24) {
        self.batchSize = max(1, batchSize)
    }

    func discover(
        in inputURLs: [URL],
        yieldBatch: @escaping @Sendable ([URL]) async -> Void
    ) async {
        var stack = inputURLs
            .map(\.standardizedFileURL)
            .reversed()
            .map { $0 }
        var seenDirectoryPaths = Set<String>()
        var seenAppPaths = Set<String>()
        var batch: [URL] = []

        while let url = stack.popLast() {
            guard Task.isCancelled == false else {
                return
            }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard resourceValues?.isSymbolicLink != true else {
                continue
            }

            if url.isAppBundlePath, resourceValues?.isDirectory == true {
                let identityPath = url.resolvingSymlinksInPath().standardizedFileURL.path
                if seenAppPaths.insert(identityPath).inserted {
                    batch.append(url)
                    if batch.count >= batchSize {
                        await yieldBatch(batch)
                        batch.removeAll(keepingCapacity: true)
                    }
                }
                continue
            }

            guard resourceValues?.isDirectory == true else {
                continue
            }

            let directoryIdentity = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seenDirectoryPaths.insert(directoryIdentity).inserted else {
                continue
            }

            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children.sorted(by: Self.pathAscending).reversed() {
                stack.append(child)
            }
        }

        if batch.isEmpty == false, Task.isCancelled == false {
            await yieldBatch(batch)
        }
    }

    private static func pathAscending(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
    }
}

private extension URL {
    var isAppBundlePath: Bool {
        pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
