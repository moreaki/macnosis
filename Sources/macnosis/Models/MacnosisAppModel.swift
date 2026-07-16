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

    private let inspector: any AppBundleInspecting
    private let appBundlePicker: AppBundlePicking
    private let repairService: any AppRepairServicing
    private let appBundleDiscovery: AppBundleDiscovery
    private let commandRunner = InspectionCommandRunner(
        maxConcurrentLightCommands: maxConcurrentLightInspectionCommands,
        maxConcurrentDeepCommands: maxConcurrentDeepInspectionCommands
    )
    private var inspectionGenerations: [InspectedApp.ID: UUID] = [:]
    private var inspectionTasks: [InspectedApp.ID: Task<Void, Never>] = [:]
    private var repairGenerations: [InspectedApp.ID: UUID] = [:]
    private var discoveryTasks: [UUID: Task<Void, Never>] = [:]

    init(
        appBundlePicker: AppBundlePicking = AppBundleOpenPanel(),
        inspector: any AppBundleInspecting = AppBundleInspector(),
        repairService: any AppRepairServicing = AppRepairService(),
        appBundleDiscovery: AppBundleDiscovery = AppBundleDiscovery()
    ) {
        self.appBundlePicker = appBundlePicker
        self.inspector = inspector
        self.repairService = repairService
        self.appBundleDiscovery = appBundleDiscovery
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
        let generation = UUID()
        inspectionTasks[id]?.cancel()
        inspectionTasks[id] = nil
        inspectionGenerations[id] = generation
        selectedAppID = id

        let initialReport: AppInspectionReport
        do {
            initialReport = try inspector.initialReport(bundleURL: normalizedURL)
        } catch {
            upsertApp(id: id, url: normalizedURL, report: nil, errorMessage: error.localizedDescription, isInspecting: false)
            inspectionGenerations[id] = nil
            return
        }

        upsertApp(id: id, url: normalizedURL, report: initialReport, errorMessage: nil, isInspecting: true)
        let commands = inspector.inspectionCommands(for: initialReport)
        let fastCommands = commands.filter { $0.isFastSummaryCommand }
        let remainingCommands = commands.filter { $0.isFastSummaryCommand == false }
        let commandRunner = commandRunner

        let task = Task.detached { [weak self, inspector] in
            guard let self else {
                return
            }

            await self.run(
                fastCommands,
                for: initialReport,
                inspector: inspector,
                commandRunner: commandRunner,
                id: id,
                generation: generation
            )
            await self.run(
                remainingCommands,
                for: initialReport,
                inspector: inspector,
                commandRunner: commandRunner,
                id: id,
                generation: generation
            )
            await MainActor.run {
                self.finishInspection(id: id, generation: generation)
            }
        }
        inspectionTasks[id] = task
    }

    func inspect(_ urls: [URL]) {
        let taskID = UUID()
        let discovery = appBundleDiscovery
        let task = Task { [weak self] in
            let worker = Task.detached { [weak self, discovery] in
                await discovery.discover(in: urls) { [weak self] batch in
                    await MainActor.run {
                        guard let self else {
                            return
                        }

                        batch.forEach(self.inspectAppBundle)
                    }
                }
            }

            await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            self?.discoveryTasks[taskID] = nil
        }
        discoveryTasks[taskID] = task
    }

    func selectApp(id: InspectedApp.ID) {
        selectedAppID = id
    }

    func closeApp(id: InspectedApp.ID) {
        inspectionTasks[id]?.cancel()
        inspectionTasks[id] = nil
        inspectionGenerations[id] = nil
        repairGenerations[id] = nil
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

    private func updateInspection(
        id: InspectedApp.ID,
        generation: UUID,
        with result: AppInspectionCommandResult
    ) {
        guard inspectionGenerations[id] == generation,
              let index = inspectedApps.firstIndex(where: { $0.id == id })
        else {
            return
        }

        inspectedApps[index].report?.apply(result)
    }

    private func finishInspection(id: InspectedApp.ID, generation: UUID) {
        guard inspectionGenerations[id] == generation,
              let index = inspectedApps.firstIndex(where: { $0.id == id })
        else {
            return
        }

        inspectedApps[index].isInspecting = false
        inspectionTasks[id] = nil
        inspectionGenerations[id] = nil
    }

    nonisolated private func run(
        _ commands: [AppInspectionCommand],
        for report: AppInspectionReport,
        inspector: any AppBundleInspecting,
        commandRunner: InspectionCommandRunning,
        id: InspectedApp.ID,
        generation: UUID
    ) async {
        guard Task.isCancelled == false else {
            return
        }

        await withTaskGroup(of: AppInspectionCommandResult?.self) { group in
            for command in commands {
                group.addTask {
                    guard Task.isCancelled == false else {
                        return nil
                    }

                    return await commandRunner.run(command, for: report, using: inspector) { lane, isActive in
                        await MainActor.run {
                            self.updateActiveCommandCount(for: lane, isActive: isActive)
                        }
                    }
                }
            }

            for await result in group {
                guard let result, Task.isCancelled == false else {
                    continue
                }

                await MainActor.run {
                    self.updateInspection(id: id, generation: generation, with: result)
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
        guard let app = inspectedApps.first(where: { $0.id == id }), app.isRepairing == false else {
            return
        }

        let generation = UUID()
        repairGenerations[id] = generation
        setRepairState(id: id, isRepairing: true, message: nil)
        let appURL = app.url
        let repairService = repairService

        Task.detached {
            let result = repairService.run(operation, appURL: appURL)
            await MainActor.run {
                self.finishRepair(operation, sourceURL: appURL, generation: generation, result: result)
            }
        }
    }

    private func finishRepair(
        _ operation: AppRepairOperation,
        sourceURL: URL,
        generation: UUID,
        result: CommandResult
    ) {
        let id = sourceURL.standardizedFileURL.path
        guard repairGenerations[id] == generation,
              inspectedApps.contains(where: { $0.id == id })
        else {
            return
        }

        repairGenerations[id] = nil
        let succeeded = result.succeeded
        setRepairState(
            id: id,
            isRepairing: false,
            message: AppActionMessage(
                text: succeeded ? "Repair action completed." : result.combinedOutput,
                isError: succeeded == false
            )
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

    private func setRepairState(id: InspectedApp.ID, isRepairing: Bool, message: AppActionMessage?) {
        guard let index = inspectedApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        inspectedApps[index].isRepairing = isRepairing
        inspectedApps[index].actionMessage = message
    }
}

protocol AppBundleInspecting: Sendable {
    func initialReport(bundleURL: URL) throws -> AppInspectionReport
    func inspectionCommands(for report: AppInspectionReport) -> [AppInspectionCommand]
    func run(_ command: AppInspectionCommand, for report: AppInspectionReport) -> AppInspectionCommandResult
}

extension AppBundleInspector: AppBundleInspecting {}

private protocol InspectionCommandRunning: Sendable {
    func run(
        _ command: AppInspectionCommand,
        for report: AppInspectionReport,
        using inspector: any AppBundleInspecting,
        activity: @escaping @Sendable (InspectionCommandLane, Bool) async -> Void
    ) async -> AppInspectionCommandResult?
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
        using inspector: any AppBundleInspecting,
        activity: @escaping @Sendable (InspectionCommandLane, Bool) async -> Void
    ) async -> AppInspectionCommandResult? {
        guard Task.isCancelled == false else {
            return nil
        }

        let lane = command.inspectionLane
        let semaphore = lane == .deep ? deepSemaphore : lightSemaphore
        await semaphore.wait()
        guard Task.isCancelled == false else {
            await semaphore.signal()
            return nil
        }

        await activity(lane, true)
        let result = inspector.run(command, for: report)
        await activity(lane, false)
        await semaphore.signal()
        return Task.isCancelled ? nil : result
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

struct InspectedApp: Identifiable, Equatable {
    let id: String
    let url: URL
    var report: AppInspectionReport?
    var errorMessage: String?
    var isInspecting: Bool
    var isRepairing: Bool
    var actionMessage: AppActionMessage?

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

        if report.debuggingStatus == .debuggable {
            return "Debuggable"
        }

        switch report.gatekeeperStatus {
        case .accepted:
            return report.quarantineStatus == .quarantined ? "Accepted, Quarantined" : "Accepted"
        case .rejected:
            return "Gatekeeper Rejected"
        case .pending, .unknown, .unavailable:
            break
        }

        switch report.signatureVerificationStatus {
        case .valid:
            return "Checked"
        case .invalid:
            return "Signature Issue"
        case .pending:
            return isInspecting ? "Checking" : "Checked"
        case .unavailable:
            return "Inspection Incomplete"
        }
    }

    var hasWarning: Bool {
        guard let report else {
            return errorMessage != nil
        }

        return errorMessage != nil
            || report.signatureVerificationStatus == .invalid
            || report.gatekeeperStatus == .rejected
            || report.quarantineStatus == .quarantined
    }
}

struct AppActionMessage: Equatable {
    let text: String
    let isError: Bool
}
