import Foundation
import MacnosisCore
import XCTest
@testable import macnosis

@MainActor
final class MacnosisAppModelTests: XCTestCase {
    func testClosedAndReaddedBundleIgnoresStaleInspectionResults() async throws {
        let appURL = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisModelTests-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appURL) }

        let inspector = SequencedInspector()
        let model = MacnosisAppModel(inspector: inspector)
        let appID = appURL.standardizedFileURL.path

        model.inspect(appURL)
        try await waitUntil { inspector.startedCount >= 1 }
        model.closeApp(id: appID)
        model.inspect(appURL)

        try await waitUntil {
            model.inspectedApps.first?.report?.teamIdentifier == "NEW"
                && model.inspectedApps.first?.isInspecting == false
        }

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.inspectedApps.first?.report?.teamIdentifier, "NEW")
        XCTAssertFalse(model.inspectedApps.first?.isInspecting ?? true)
    }

    func testClosedAndReaddedBundleIgnoresStaleRepairResult() async throws {
        let appURL = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisRepairModelTests-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appURL) }

        let inspector = ImmediateInspector()
        let repairService = DelayedRepairService()
        let model = MacnosisAppModel(inspector: inspector, repairService: repairService)
        let appID = appURL.standardizedFileURL.path

        model.inspect(appURL)
        try await waitUntil { model.inspectedApps.first?.isInspecting == false }
        model.clearQuarantine(for: appID)
        try await waitUntil { repairService.startedCount == 1 }
        model.closeApp(id: appID)
        model.inspect(appURL)

        try await waitUntil {
            model.inspectedApps.first?.isInspecting == false
                && inspector.initialReportCount == 2
        }
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(inspector.initialReportCount, 2)
        XCTAssertNil(model.inspectedApps.first?.actionMessage)
        XCTAssertFalse(model.inspectedApps.first?.isRepairing ?? true)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while condition() == false {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for model state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class ImmediateInspector: AppBundleInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var reportCount = 0

    var initialReportCount: Int {
        lock.withLock { reportCount }
    }

    func initialReport(bundleURL: URL) throws -> AppInspectionReport {
        lock.withLock { reportCount += 1 }
        return AppInspectionReport(
            bundleURL: bundleURL,
            bundleName: "Fixture",
            bundleIdentifier: "example.fixture",
            version: "1",
            buildVersion: "1",
            bundleInfoString: nil,
            executableName: nil,
            executableURL: nil,
            executableFileDescription: nil
        )
    }

    func inspectionCommands(for report: AppInspectionReport) -> [AppInspectionCommand] {
        []
    }

    func run(_ command: AppInspectionCommand, for report: AppInspectionReport) -> AppInspectionCommandResult {
        fatalError("ImmediateInspector has no commands")
    }
}

private final class DelayedRepairService: AppRepairServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var runCount = 0

    var startedCount: Int {
        lock.withLock { runCount }
    }

    func run(_ operation: AppRepairOperation, appURL: URL) -> CommandResult {
        lock.withLock { runCount += 1 }
        Thread.sleep(forTimeInterval: 0.15)
        return CommandResult(command: ["repair"], exitCode: 0, standardOutput: "", standardError: "")
    }

    func debuggableCopyURL(for appURL: URL) -> URL {
        appURL.deletingLastPathComponent().appending(path: "Fixture-debug.app")
    }
}

private final class SequencedInspector: AppBundleInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var runCount = 0

    var startedCount: Int {
        lock.withLock { runCount }
    }

    func initialReport(bundleURL: URL) throws -> AppInspectionReport {
        AppInspectionReport(
            bundleURL: bundleURL,
            bundleName: "Fixture",
            bundleIdentifier: "example.fixture",
            version: "1",
            buildVersion: "1",
            bundleInfoString: nil,
            executableName: "Fixture",
            executableURL: nil,
            executableFileDescription: nil
        )
    }

    func inspectionCommands(for report: AppInspectionReport) -> [AppInspectionCommand] {
        [.signingDetails]
    }

    func run(_ command: AppInspectionCommand, for report: AppInspectionReport) -> AppInspectionCommandResult {
        let sequence = lock.withLock {
            runCount += 1
            return runCount
        }
        Thread.sleep(forTimeInterval: sequence == 1 ? 0.25 : 0.02)
        let teamIdentifier = sequence == 1 ? "OLD" : "NEW"
        return AppInspectionCommandResult(
            command: command,
            result: CommandResult(
                command: ["codesign"],
                exitCode: 0,
                standardOutput: "",
                standardError: "TeamIdentifier=\(teamIdentifier)"
            )
        )
    }
}
