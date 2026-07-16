import Darwin
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
        var seenDirectoryIdentities = Set<FileSystemIdentity>()
        var seenAppIdentities = Set<FileSystemIdentity>()
        var batch: [URL] = []

        while let url = stack.popLast() {
            guard Task.isCancelled == false else {
                return
            }

            guard let metadata = FileSystemEntryMetadata(url: url), metadata.isSymbolicLink == false else {
                continue
            }

            if url.isAppBundlePath, metadata.isDirectory {
                if seenAppIdentities.insert(metadata.identity).inserted {
                    batch.append(url)
                    if seenAppIdentities.count == 1 || batch.count >= batchSize {
                        await yieldBatch(batch)
                        batch.removeAll(keepingCapacity: true)
                    }
                }
                continue
            }

            guard metadata.isDirectory else {
                continue
            }

            guard seenDirectoryIdentities.insert(metadata.identity).inserted else {
                continue
            }

            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
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

private struct FileSystemEntryMetadata {
    let identity: FileSystemIdentity
    let isDirectory: Bool
    let isSymbolicLink: Bool

    init?(url: URL) {
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.lstat(path, &status)
        }
        guard result == 0 else {
            return nil
        }

        identity = FileSystemIdentity(device: status.st_dev, inode: status.st_ino)
        let fileType = status.st_mode & mode_t(S_IFMT)
        isDirectory = fileType == mode_t(S_IFDIR)
        isSymbolicLink = fileType == mode_t(S_IFLNK)
    }
}

private struct FileSystemIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
}

private extension URL {
    var isAppBundlePath: Bool {
        pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
