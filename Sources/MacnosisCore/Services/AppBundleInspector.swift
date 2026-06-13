import Darwin
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
            executableFileDescription: executableURL.flatMap { run(["/usr/bin/file", $0.path], timeout: 5).combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines) },
            signingDetails: run(["/usr/bin/codesign", "-dv", "--verbose=4", normalizedURL.path], timeout: 10),
            entitlements: run(["/usr/bin/codesign", "-d", "--entitlements", ":-", normalizedURL.path], timeout: 10),
            signatureVerification: run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", normalizedURL.path], timeout: 45),
            gatekeeperAssessment: run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", normalizedURL.path], timeout: 20),
            extendedAttributes: run(["/usr/bin/xattr", "-lr", normalizedURL.path], timeout: 20)
        )
    }

    private func run(_ command: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())

        let captureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Macnosis-\(UUID().uuidString)", directoryHint: .isDirectory)
        let standardOutputURL = captureDirectory.appending(path: "stdout.txt")
        let standardErrorURL = captureDirectory.appending(path: "stderr.txt")

        do {
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
            FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)

            let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
            let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
            defer {
                try? standardOutputHandle.close()
                try? standardErrorHandle.close()
                try? FileManager.default.removeItem(at: captureDirectory)
            }

            process.standardOutput = standardOutputHandle
            process.standardError = standardErrorHandle

            let terminationSemaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                terminationSemaphore.signal()
            }

            try process.run()

            let timedOut = terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()

                if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }

            try standardOutputHandle.close()
            try standardErrorHandle.close()

            let standardOutput = String(decoding: try Data(contentsOf: standardOutputURL), as: UTF8.self)
            let standardError = String(decoding: try Data(contentsOf: standardErrorURL), as: UTF8.self)
            let timeoutMessage = timedOut ? "\nCommand timed out after \(Int(timeout)) seconds." : ""

            return CommandResult(
                command: command,
                exitCode: timedOut ? 124 : process.terminationStatus,
                standardOutput: standardOutput,
                standardError: standardError + timeoutMessage
            )
        } catch {
            return CommandResult(
                command: command,
                exitCode: 127,
                standardOutput: "",
                standardError: String(describing: error)
            )
        }
    }
}
