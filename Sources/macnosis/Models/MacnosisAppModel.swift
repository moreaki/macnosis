import Foundation
import MacnosisCore
import UniformTypeIdentifiers

@MainActor
final class MacnosisAppModel: ObservableObject {
    @Published var selectedAppURL: URL?
    @Published var report: AppInspectionReport?
    @Published var errorMessage: String?
    @Published var isInspecting = false
    @Published var isImporterPresented = false

    private let inspector = AppBundleInspector()

    func chooseApp() {
        isImporterPresented = true
    }

    func inspect(_ url: URL) {
        selectedAppURL = url
        report = nil
        errorMessage = nil
        isInspecting = true

        Task { @MainActor in
            do {
                report = try inspector.inspect(bundleURL: url)
            } catch {
                errorMessage = error.localizedDescription
            }
            isInspecting = false
        }
    }

    var appImportTypes: [UTType] {
        [UTType(filenameExtension: "app") ?? .applicationBundle]
    }
}
