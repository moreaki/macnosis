import Foundation

public struct AppBundleInspector: Sendable {
    public init() {}

    public func inspect(bundleURL: URL) throws -> AppInspectionReport {
        let normalizedURL = bundleURL.standardizedFileURL
        guard normalizedURL.pathExtension == "app" else {
            throw AppInspectionError.notAppBundle(normalizedURL)
        }

        let infoPlistURL = normalizedURL.appending(path: "Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw AppInspectionError.missingInfoPlist(infoPlistURL)
        }

        let info = NSDictionary(contentsOf: infoPlistURL) as? [String: Any] ?? [:]
        let executableName = info["CFBundleExecutable"] as? String
        let executableURL = executableName.map {
            normalizedURL.appending(path: "Contents/MacOS").appending(path: $0)
        }

        return AppInspectionReport(
            bundleURL: normalizedURL,
            bundleName: info["CFBundleDisplayName"] as? String
                ?? info["CFBundleName"] as? String
                ?? normalizedURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            version: info["CFBundleShortVersionString"] as? String,
            executableName: executableName,
            executableURL: executableURL,
            executableFileDescription: executableURL.flatMap { run(["/usr/bin/file", $0.path]).combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines) },
            signingDetails: run(["/usr/bin/codesign", "-dv", "--verbose=4", normalizedURL.path]),
            entitlements: run(["/usr/bin/codesign", "-d", "--entitlements", ":-", normalizedURL.path]),
            signatureVerification: run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", normalizedURL.path]),
            gatekeeperAssessment: run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", normalizedURL.path]),
            extendedAttributes: run(["/usr/bin/xattr", "-lr", normalizedURL.path])
        )
    }

    private func run(_ command: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(
                command: command,
                exitCode: 127,
                standardOutput: "",
                standardError: String(describing: error)
            )
        }

        return CommandResult(
            command: command,
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            standardError: String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
