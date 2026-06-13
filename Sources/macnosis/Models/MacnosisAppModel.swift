import Foundation
import MacnosisCore

@MainActor
final class MacnosisAppModel: ObservableObject {
    static let maxConcurrentLightInspectionCommands = 8
    static let maxConcurrentDeepInspectionCommands = 2

    @Published private(set) var inspectedApps: [InspectedApp] = []
    @Published private(set) var activeLightInspectionCommandCount = 0
    @Published private(set) var activeDeepInspectionCommandCount = 0
    @Published var selectedAppID: InspectedApp.ID?
    @Published var isDropTargeted = false

    private let inspector = AppBundleInspector()
    private let appBundlePicker: AppBundlePicking
    private let repairService = AppRepairService()
    private let commandRunner = InspectionCommandRunner(
        maxConcurrentLightCommands: maxConcurrentLightInspectionCommands,
        maxConcurrentDeepCommands: maxConcurrentDeepInspectionCommands
    )

    init(appBundlePicker: AppBundlePicking = AppBundleOpenPanel()) {
        self.appBundlePicker = appBundlePicker
    }

    func chooseApp() {
        inspect(appBundlePicker.chooseAppBundles())
    }

    func inspect(_ url: URL) {
        inspect([url])
    }

    private func inspectAppBundle(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        let id = normalizedURL.path
        selectedAppID = id

        let initialReport: AppInspectionReport
        do {
            initialReport = try inspector.initialReport(bundleURL: normalizedURL)
        } catch {
            upsertApp(id: id, url: normalizedURL, report: nil, errorMessage: error.localizedDescription, isInspecting: false)
            return
        }

        upsertApp(id: id, url: normalizedURL, report: initialReport, errorMessage: nil, isInspecting: true)
        let commands = inspector.inspectionCommands(for: initialReport)
        let fastCommands = commands.filter { $0.isFastSummaryCommand }
        let remainingCommands = commands.filter { $0.isFastSummaryCommand == false }
        let commandRunner = commandRunner

        Task.detached { [inspector] in
            await self.run(fastCommands, for: initialReport, inspector: inspector, commandRunner: commandRunner, id: id)
            await self.run(remainingCommands, for: initialReport, inspector: inspector, commandRunner: commandRunner, id: id)
            await MainActor.run {
                self.finishInspection(id: id)
            }
        }
    }

    func inspect(_ urls: [URL]) {
        Self.appBundleURLs(in: urls)
            .forEach(inspectAppBundle)
    }

    func selectApp(id: InspectedApp.ID) {
        selectedAppID = id
    }

    func closeApp(id: InspectedApp.ID) {
        inspectedApps.removeAll { $0.id == id }

        if selectedAppID == id {
            selectedAppID = inspectedApps.last?.id
        }
    }

    var selectedApp: InspectedApp? {
        guard let selectedAppID else {
            return inspectedApps.last
        }

        return inspectedApps.first { $0.id == selectedAppID }
    }

    var activeInspectionCount: Int {
        inspectedApps.filter(\.isInspecting).count
    }

    var lightInspectionWorkerCount: Int {
        Self.maxConcurrentLightInspectionCommands
    }

    var deepInspectionWorkerCount: Int {
        Self.maxConcurrentDeepInspectionCommands
    }

    private func upsertApp(id: InspectedApp.ID, url: URL, report: AppInspectionReport?, errorMessage: String?, isInspecting: Bool) {
        if let index = inspectedApps.firstIndex(where: { $0.id == id }) {
            inspectedApps[index].report = report
            inspectedApps[index].errorMessage = errorMessage
            inspectedApps[index].isInspecting = isInspecting
        } else {
            inspectedApps.append(
                InspectedApp(
                    id: id,
                    url: url,
                    report: report,
                    errorMessage: errorMessage,
                    isInspecting: isInspecting,
                    isRepairing: false,
                    actionMessage: nil
                )
            )
        }
    }

    private func updateInspection(id: InspectedApp.ID, with result: AppInspectionCommandResult) {
        guard let index = inspectedApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        inspectedApps[index].report?.apply(result)
    }

    private func finishInspection(id: InspectedApp.ID) {
        guard let index = inspectedApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        inspectedApps[index].isInspecting = false
    }

    nonisolated private func run(
        _ commands: [AppInspectionCommand],
        for report: AppInspectionReport,
        inspector: AppBundleInspector,
        commandRunner: InspectionCommandRunning,
        id: InspectedApp.ID
    ) async {
        await withTaskGroup(of: AppInspectionCommandResult.self) { group in
            for command in commands {
                group.addTask {
                    await commandRunner.run(command, for: report, using: inspector) { lane, isActive in
                        await MainActor.run {
                            self.updateActiveCommandCount(for: lane, isActive: isActive)
                        }
                    }
                }
            }

            for await result in group {
                await MainActor.run {
                    self.updateInspection(id: id, with: result)
                }
            }
        }
    }

    private func updateActiveCommandCount(for lane: InspectionCommandLane, isActive: Bool) {
        switch lane {
        case .light:
            activeLightInspectionCommandCount = max(0, activeLightInspectionCommandCount + (isActive ? 1 : -1))
        case .deep:
            activeDeepInspectionCommandCount = max(0, activeDeepInspectionCommandCount + (isActive ? 1 : -1))
        }
    }

    func clearQuarantine(for id: InspectedApp.ID) {
        runRepair(.clearQuarantine, for: id)
    }

    func createDebuggableCopy(for id: InspectedApp.ID) {
        runRepair(.createDebuggableCopy, for: id)
    }

    func repairDamagedInPlace(for id: InspectedApp.ID) {
        runRepair(.repairDamagedInPlace, for: id)
    }

    private func runRepair(_ operation: AppRepairOperation, for id: InspectedApp.ID) {
        guard let app = inspectedApps.first(where: { $0.id == id }) else {
            return
        }

        setRepairState(id: id, isRepairing: true, message: "Running repair action...")
        let appURL = app.url
        let repairService = repairService

        Task.detached {
            let result = repairService.run(operation, appURL: appURL)
            await MainActor.run {
                self.finishRepair(operation, sourceURL: appURL, result: result)
            }
        }
    }

    private func finishRepair(_ operation: AppRepairOperation, sourceURL: URL, result: CommandResult) {
        let id = sourceURL.standardizedFileURL.path
        let succeeded = result.exitCode == 0
        setRepairState(
            id: id,
            isRepairing: false,
            message: succeeded ? "Repair action completed." : result.combinedOutput
        )

        switch operation {
        case .clearQuarantine, .repairDamagedInPlace:
            inspect(sourceURL)
        case .createDebuggableCopy:
            if succeeded {
                inspect(repairService.debuggableCopyURL(for: sourceURL))
            }
        }
    }

    private func setRepairState(id: InspectedApp.ID, isRepairing: Bool, message: String?) {
        guard let index = inspectedApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        inspectedApps[index].isRepairing = isRepairing
        inspectedApps[index].actionMessage = message
    }
}

private extension MacnosisAppModel {
    nonisolated static func appBundleURLs(in urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var resolvedAppBundleURLs: [URL] = []

        for url in urls {
            for appBundleURL in appBundleURLs(in: url.standardizedFileURL) {
                let path = appBundleURL.path
                guard seenPaths.insert(path).inserted else {
                    continue
                }

                resolvedAppBundleURLs.append(appBundleURL)
            }
        }

        return resolvedAppBundleURLs
    }

    nonisolated static func appBundleURLs(in url: URL) -> [URL] {
        if url.isAppBundlePath {
            return [url]
        }

        guard url.isDirectory else {
            return []
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .flatMap(appBundleURLs)
    }
}

private protocol InspectionCommandRunning: Sendable {
    func run(
        _ command: AppInspectionCommand,
        for report: AppInspectionReport,
        using inspector: AppBundleInspector,
        activity: @escaping @Sendable (InspectionCommandLane, Bool) async -> Void
    ) async -> AppInspectionCommandResult
}

private enum InspectionCommandLane: Sendable {
    case light
    case deep
}

private final class InspectionCommandRunner: InspectionCommandRunning, @unchecked Sendable {
    private let lightSemaphore: AsyncSemaphore
    private let deepSemaphore: AsyncSemaphore

    init(maxConcurrentLightCommands: Int, maxConcurrentDeepCommands: Int) {
        lightSemaphore = AsyncSemaphore(value: max(1, maxConcurrentLightCommands))
        deepSemaphore = AsyncSemaphore(value: max(1, maxConcurrentDeepCommands))
    }

    func run(
        _ command: AppInspectionCommand,
        for report: AppInspectionReport,
        using inspector: AppBundleInspector,
        activity: @escaping @Sendable (InspectionCommandLane, Bool) async -> Void
    ) async -> AppInspectionCommandResult {
        let lane = command.inspectionLane
        let semaphore = lane == .deep ? deepSemaphore : lightSemaphore
        await semaphore.wait()
        await activity(lane, true)
        let result = inspector.run(command, for: report)
        await activity(lane, false)
        await semaphore.signal()
        return result
    }
}

private actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private extension AppInspectionCommand {
    var isFastSummaryCommand: Bool {
        self == .executableFileDescription
    }

    var inspectionLane: InspectionCommandLane {
        switch self {
        case .signatureVerification, .gatekeeperAssessment:
            return .deep
        case .executableFileDescription, .signingDetails, .entitlements, .extendedAttributes:
            return .light
        }
    }
}

private extension URL {
    var isAppBundlePath: Bool {
        pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

struct InspectedApp: Identifiable, Equatable {
    let id: String
    let url: URL
    var report: AppInspectionReport?
    var errorMessage: String?
    var isInspecting: Bool
    var isRepairing: Bool
    var actionMessage: String?

    var displayName: String {
        packageName
    }

    var packageName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var statusText: String {
        if isRepairing {
            return "Repairing"
        }

        if errorMessage != nil {
            return "Blocked"
        }

        guard let report else {
            return isInspecting ? "Inspecting" : "Queued"
        }

        if report.hasEntitlements && report.isDebuggable {
            return "Debuggable"
        }

        if report.hasGatekeeperAssessment {
            switch report.gatekeeperStatus {
            case .accepted:
                return report.hasExtendedAttributes && report.isQuarantined ? "Accepted, Quarantined" : "Accepted"
            case .rejected:
                return "Gatekeeper Rejected"
            case .unknown:
                break
            }
        }

        if report.hasSignatureVerification {
            return report.isSignatureValid ? "Checked" : "Signature Issue"
        }

        return isInspecting ? "Checking" : "Checked"
    }

    var hasWarning: Bool {
        guard let report else {
            return errorMessage != nil
        }

        return errorMessage != nil
            || (report.hasSignatureVerification && report.isSignatureValid == false)
            || (report.hasGatekeeperAssessment && report.gatekeeperStatus == .rejected)
            || (report.hasExtendedAttributes && report.isQuarantined)
    }
}
