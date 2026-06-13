import Foundation

@MainActor
protocol AppBundlePicking {
    func chooseAppBundles() -> [URL]
}
