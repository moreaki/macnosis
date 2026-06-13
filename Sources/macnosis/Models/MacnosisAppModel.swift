import Foundation
import MacnosisCore

@MainActor
final class MacnosisAppModel: ObservableObject {
    @Published private(set) var inspectedApps: [InspectedApp] = []
    @Published var selectedAppID: InspectedApp.ID?
    @Published var isDropTargeted = false

    private let inspector = AppBundleInspector()
    private let appBundlePicker: AppBundlePicking

    init(appBundlePicker: AppBundlePicking = AppBundleOpenPanel()) {
        self.appBundlePicker = appBundlePicker
    }

    func chooseApp() {
        inspect(appBundlePicker.chooseAppBundles())
    }

    func inspect(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        let id = normalizedURL.path
        selectedAppID = id

        if let index = inspectedApps.firstIndex(where: { $0.id == id }) {
            inspectedApps[index].isInspecting = true
            inspectedApps[index].errorMessage = nil
        } else {
            inspectedApps.append(
                InspectedApp(
                    id: id,
                    url: normalizedURL,
                    report: nil,
                    errorMessage: nil,
                    isInspecting: true
                )
            )
        }

        Task.detached { [inspector] in
            do {
                let report = try inspector.inspect(bundleURL: normalizedURL)
                await MainActor.run {
                    self.updateInspection(id: id, report: report, errorMessage: nil)
                }
            } catch {
                await MainActor.run {
                    self.updateInspection(id: id, report: nil, errorMessage: error.localizedDescription)
                }
            }
        }
    }

    func inspect(_ urls: [URL]) {
        urls
            .filter { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame }
            .forEach(inspect)
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

    private func updateInspection(id: InspectedApp.ID, report: AppInspectionReport?, errorMessage: String?) {
        guard let index = inspectedApps.firstIndex(where: { $0.id == id }) else {
            return
        }

        inspectedApps[index].report = report
        inspectedApps[index].errorMessage = errorMessage
        inspectedApps[index].isInspecting = false
    }
}

struct InspectedApp: Identifiable, Equatable {
    let id: String
    let url: URL
    var report: AppInspectionReport?
    var errorMessage: String?
    var isInspecting: Bool

    var displayName: String {
        packageName
    }

    var packageName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var statusText: String {
        if isInspecting {
            return "Inspecting"
        }

        if errorMessage != nil {
            return "Blocked"
        }

        guard let report else {
            return "Queued"
        }

        if report.isDebuggable {
            return "Debuggable"
        }

        switch report.gatekeeperStatus {
        case .accepted:
            return report.isQuarantined ? "Accepted, Quarantined" : "Accepted"
        case .rejected:
            return "Gatekeeper Rejected"
        case .unknown:
            return report.isSignatureValid ? "Checked" : "Signature Issue"
        }
    }

    var hasWarning: Bool {
        guard let report else {
            return errorMessage != nil
        }

        return errorMessage != nil
            || report.isSignatureValid == false
            || report.gatekeeperStatus == .rejected
            || report.isQuarantined
    }
}
