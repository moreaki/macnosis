import Foundation
import XCTest
@testable import macnosis

final class AppBundleDiscoveryTests: XCTestCase {
    func testDiscoveryIsDeterministicDeduplicatedBatchedAndSkipsSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisDiscoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstApp = root.appending(path: "A.app", directoryHint: .isDirectory)
        let folder = root.appending(path: "Folder", directoryHint: .isDirectory)
        let secondApp = folder.appending(path: "B.APP", directoryHint: .isDirectory)
        let hiddenApp = root.appending(path: ".Hidden.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hiddenApp, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "Loop"),
            withDestinationURL: root
        )
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "Linked.app"),
            withDestinationURL: firstApp
        )

        let collector = DiscoveryCollector()
        await AppBundleDiscovery(batchSize: 24).discover(in: [root, firstApp]) { batch in
            await collector.append(batch)
        }

        let result = await collector.snapshot()
        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["A.app", "B.APP"])
        XCTAssertEqual(result.batchCount, 2)
    }

    func testOverlappingAliasRootsAreTraversedOnlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisDiscoveryIdentityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = root.appending(path: "Folder", directoryHint: .isDirectory)
        let initialApp = folder.appending(path: "B.app", directoryHint: .isDirectory)
        let lateApp = folder.appending(path: "C.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: initialApp, withIntermediateDirectories: true)

        let collector = DiscoveryCollector()
        await AppBundleDiscovery().discover(in: [root, folder]) { batch in
            await collector.append(batch)
            if batch.contains(where: { $0.lastPathComponent == initialApp.lastPathComponent }) {
                try? FileManager.default.createDirectory(at: lateApp, withIntermediateDirectories: true)
            }
        }

        let result = await collector.snapshot()
        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["B.app"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: lateApp.path))
    }
}

private actor DiscoveryCollector {
    private var urls: [URL] = []
    private var batchCount = 0

    func append(_ batch: [URL]) {
        urls.append(contentsOf: batch)
        batchCount += 1
    }

    func snapshot() -> (urls: [URL], batchCount: Int) {
        (urls, batchCount)
    }
}
