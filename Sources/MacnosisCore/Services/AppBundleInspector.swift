import Foundation

public struct AppBundleInspector: Sendable {
    private let commandExecutor: CommandExecutor
    private let executableMetadataReader: ExecutableMetadataReader
    private let codeSigningMetadataReader: CodeSigningMetadataReader
    private let signatureVerificationReader: SignatureVerificationReader
    private let bundleAttributeReader: BundleAttributeReader

    public init(
        commandExecutor: CommandExecutor = CommandExecutor(),
        executableMetadataReader: ExecutableMetadataReader = ExecutableMetadataReader(),
        codeSigningMetadataReader: CodeSigningMetadataReader = CodeSigningMetadataReader(),
        signatureVerificationReader: SignatureVerificationReader = SignatureVerificationReader(),
        bundleAttributeReader: BundleAttributeReader = BundleAttributeReader()
    ) {
        self.commandExecutor = commandExecutor
        self.executableMetadataReader = executableMetadataReader
        self.codeSigningMetadataReader = codeSigningMetadataReader
        self.signatureVerificationReader = signatureVerificationReader
        self.bundleAttributeReader = bundleAttributeReader
    }

    public func inspect(bundleURL: URL) throws -> AppInspectionReport {
        var report = try initialReport(bundleURL: bundleURL)
        for command in inspectionCommands(for: report) {
            report.apply(run(command, for: report))
        }

        return report
    }

    public func initialReport(bundleURL: URL) throws -> AppInspectionReport {
        let normalizedURL = bundleURL.standardizedFileURL
        guard normalizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
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
            case .signingMetadata, .signatureVerification, .gatekeeperAssessment, .extendedAttributes:
                return true
            }
        }
    }

    public func run(_ command: AppInspectionCommand, for report: AppInspectionReport) -> AppInspectionCommandResult {
        let commandResult: CommandResult

        switch command {
        case .executableFileDescription:
            if let executableURL = report.executableURL {
                commandResult = executableMetadataReader.read(
                    bundleURL: report.bundleURL,
                    executableURL: executableURL
                ) ?? commandExecutor.run(["/usr/bin/file", executableURL.path], timeout: 5)
            } else {
                commandResult = CommandResult(
                    command: ["/usr/bin/file"],
                    termination: .failedToLaunch,
                    standardOutput: "",
                    standardError: "No executable was found in the app bundle."
                )
            }
        case .signingMetadata:
            commandResult = codeSigningMetadataReader.read(bundleURL: report.bundleURL)
        case .signatureVerification:
            commandResult = signatureVerificationReader.read(
                bundleURL: report.bundleURL,
                commandExecutor: commandExecutor
            )
        case .gatekeeperAssessment:
            commandResult = commandExecutor.run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", report.bundleURL.path], timeout: 60)
        case .extendedAttributes:
            commandResult = bundleAttributeReader.read(bundleURL: report.bundleURL)
        }

        return AppInspectionCommandResult(command: command, result: commandResult)
    }
}
