import AppKit

@MainActor
struct AppBundleOpenPanel: AppBundlePicking {
    func chooseAppBundles() -> [URL] {
        let panel = NSOpenPanel()
        let delegate = AppBundleOpenPanelDelegate()

        panel.title = "Inspect App"
        panel.message = "Choose one or more macOS .app bundles to inspect."
        panel.prompt = "Inspect"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.delegate = delegate

        return panel.runModal() == .OK ? panel.urls : []
    }
}

private final class AppBundleOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        url.hasDirectoryPath || url.isAppBundlePath
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard url.isAppBundlePath else {
            throw AppBundleOpenPanelError.notAppBundle(url)
        }
    }
}

private enum AppBundleOpenPanelError: LocalizedError {
    case notAppBundle(URL)

    var errorDescription: String? {
        switch self {
        case .notAppBundle(let url):
            return "\(url.lastPathComponent) is not a macOS .app bundle."
        }
    }
}

private extension URL {
    var isAppBundlePath: Bool {
        pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
