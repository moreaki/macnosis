import AppKit

@MainActor
struct AppBundleOpenPanel: AppBundlePicking {
    func chooseAppBundles() -> [URL] {
        let panel = NSOpenPanel()
        let delegate = AppBundleOpenPanelDelegate()

        panel.title = "Inspect Apps"
        panel.message = "Choose app bundles, or choose a folder to inspect app bundles inside it."
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
        // Non-app inputs are resolved by the model. Folders are scanned, and
        // other unsupported items are ignored without interrupting selection.
    }
}

private extension URL {
    var isAppBundlePath: Bool {
        pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
