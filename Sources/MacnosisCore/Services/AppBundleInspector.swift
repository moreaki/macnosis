import Darwin
import Foundation

public struct AppBundleInspector: Sendable {
    public init() {}

    public func inspect(bundleURL: URL) throws -> AppInspectionReport {
        var report = try initialReport(bundleURL: bundleURL)
        for command in inspectionCommands(for: report) {
            report.apply(run(command, for: report))
        }

        return report
    }

    public func initialReport(bundleURL: URL) throws -> AppInspectionReport {
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
            buildVersion: info["CFBundleVersion"] as? String,
            bundleInfoString: info["CFBundleGetInfoString"] as? String,
            executableName: executableName,
            executableURL: executableURL,
            executableFileDescription: nil
        )
    }

    public func inspectionCommands(for report: AppInspectionReport) -> [AppInspectionCommand] {
        AppInspectionCommand.allCases.filter { command in
            switch command {
            case .executableFileDescription:
                return report.executableURL != nil
            case .signingDetails, .entitlements, .signatureVerification, .gatekeeperAssessment, .extendedAttributes:
                return true
            }
        }
    }

    public func run(_ command: AppInspectionCommand, for report: AppInspectionReport) -> AppInspectionCommandResult {
        let commandResult: CommandResult

        switch command {
        case .executableFileDescription:
            if let executableURL = report.executableURL {
                commandResult = run(["/usr/bin/file", executableURL.path], timeout: 5)
            } else {
                commandResult = CommandResult(command: ["/usr/bin/file"], exitCode: 127, standardOutput: "", standardError: "No executable was found in the app bundle.")
            }
        case .signingDetails:
            commandResult = run(["/usr/bin/codesign", "-dv", "--verbose=4", report.bundleURL.path], timeout: 10)
        case .entitlements:
            commandResult = run(["/usr/bin/codesign", "-d", "--entitlements", ":-", report.bundleURL.path], timeout: 10)
        case .signatureVerification:
            commandResult = run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", report.bundleURL.path], timeout: 45)
        case .gatekeeperAssessment:
            commandResult = run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", report.bundleURL.path], timeout: 60)
        case .extendedAttributes:
            commandResult = run(["/usr/bin/xattr", "-lr", report.bundleURL.path], timeout: 20)
        }

        return AppInspectionCommandResult(command: command, result: commandResult)
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
