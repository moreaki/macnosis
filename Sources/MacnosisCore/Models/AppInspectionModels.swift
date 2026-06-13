import Foundation

public struct AppInspectionReport: Equatable, Sendable {
    public let bundleURL: URL
    public let bundleName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let buildVersion: String?
    public let bundleInfoString: String?
    public let executableName: String?
    public let executableURL: URL?
    public var executableFileDescription: String?
    public var signingDetails: CommandResult?
    public var entitlements: CommandResult?
    public var signatureVerification: CommandResult?
    public var gatekeeperAssessment: CommandResult?
    public var extendedAttributes: CommandResult?

    public init(
        bundleURL: URL,
        bundleName: String,
        bundleIdentifier: String?,
        version: String?,
        buildVersion: String?,
        bundleInfoString: String?,
        executableName: String?,
        executableURL: URL?,
        executableFileDescription: String?,
        signingDetails: CommandResult? = nil,
        entitlements: CommandResult? = nil,
        signatureVerification: CommandResult? = nil,
        gatekeeperAssessment: CommandResult? = nil,
        extendedAttributes: CommandResult? = nil
    ) {
        self.bundleURL = bundleURL
        self.bundleName = bundleName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.buildVersion = buildVersion
        self.bundleInfoString = bundleInfoString
        self.executableName = executableName
        self.executableURL = executableURL
        self.executableFileDescription = executableFileDescription
        self.signingDetails = signingDetails
        self.entitlements = entitlements
        self.signatureVerification = signatureVerification
        self.gatekeeperAssessment = gatekeeperAssessment
        self.extendedAttributes = extendedAttributes
    }

    public var hasExecutableFileDescription: Bool {
        executableFileDescription != nil
    }

    public var hasSigningDetails: Bool {
        signingDetails != nil
    }

    public var hasEntitlements: Bool {
        entitlements != nil
    }

    public var hasSignatureVerification: Bool {
        signatureVerification != nil
    }

    public var hasGatekeeperAssessment: Bool {
        gatekeeperAssessment != nil
    }

    public var hasExtendedAttributes: Bool {
        extendedAttributes != nil
    }

    public var isFullyInspected: Bool {
        let executableIsResolved = executableURL == nil || hasExecutableFileDescription
        return executableIsResolved
            && hasSigningDetails
            && hasEntitlements
            && hasSignatureVerification
            && hasGatekeeperAssessment
            && hasExtendedAttributes
    }

    public var isQuarantined: Bool {
        extendedAttributes?.combinedOutput.contains("com.apple.quarantine") == true
    }

    public var isSignatureValid: Bool {
        signatureVerification?.exitCode == 0
    }

    public var gatekeeperStatus: GatekeeperStatus {
        guard let gatekeeperAssessment else {
            return .unknown
        }

        let output = gatekeeperAssessment.combinedOutput
        if gatekeeperAssessment.exitCode == 0 || output.contains(": accepted") {
            return .accepted
        }

        if output.contains(": rejected") {
            return .rejected
        }

        return .unknown
    }

    public var isAdHocSigned: Bool {
        signingDetails?.combinedOutput.contains("Signature=adhoc") == true
            || signingDetails?.combinedOutput.contains("TeamIdentifier=not set") == true
    }

    public var hasDeveloperIDSignature: Bool {
        signingDetails?.combinedOutput.contains("Authority=Developer ID Application") == true
    }

    public var developerIDAuthority: String? {
        signingAuthorityChain.first { authority in
            authority.hasPrefix("Developer ID Application")
        }
    }

    public var teamIdentifier: String? {
        guard let teamIdentifier = signingValue(named: "TeamIdentifier"),
              teamIdentifier != "not set"
        else {
            return nil
        }

        return teamIdentifier
    }

    public var signingAuthorityChain: [String] {
        guard let signingDetails else {
            return []
        }

        return signingDetails.combinedOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                signingValue(named: "Authority", in: String(line))
            }
    }

    public var isDebuggable: Bool {
        entitlements?.combinedOutput.contains("com.apple.security.get-task-allow") == true
    }

    public var architectureSummary: String {
        executableFileDescription ?? "Unknown"
    }

    public var builderSummary: String? {
        guard let bundleInfoString = sanitizedMetadata(bundleInfoString) else {
            return nil
        }

        let comparableValues = [
            sanitizedMetadata(version),
            sanitizedMetadata(buildVersion),
        ]

        if comparableValues.contains(bundleInfoString) {
            return nil
        }

        return bundleInfoString
    }

    public var architectures: [AppArchitecture] {
        let output = architectureSummary.lowercased()
        if output.contains("shell script") || output.contains("script text executable") {
            return [.script]
        }

        let hasAppleSilicon = output.contains("arm64") || output.contains("arm64e")
        let hasIntel64 = output.contains("x86_64")
        let hasIntel32 = output.contains("i386")

        if hasAppleSilicon, hasIntel64 {
            return [.universal]
        }

        var architectures: [AppArchitecture] = []
        if hasAppleSilicon {
            architectures.append(.appleSilicon)
        }
        if hasIntel64 {
            architectures.append(.intel64)
        }
        if hasIntel32 {
            architectures.append(.intel32)
        }

        if architectures.isEmpty, output.contains("executable"), output.contains("mach-o") == false {
            return [.nonMachO]
        }

        return architectures.isEmpty ? [.unknown] : architectures
    }

    private func signingValue(named name: String) -> String? {
        guard let signingDetails else {
            return nil
        }

        return signingDetails.combinedOutput
            .split(whereSeparator: \.isNewline)
            .lazy
            .compactMap { line in
                signingValue(named: name, in: String(line))
            }
            .first
    }

    private func signingValue(named name: String, in line: String) -> String? {
        let prefix = "\(name)="
        guard line.hasPrefix(prefix) else {
            return nil
        }

        return String(line.dropFirst(prefix.count))
    }

    private func sanitizedMetadata(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    public mutating func apply(_ result: AppInspectionCommandResult) {
        switch result.command {
        case .executableFileDescription:
            executableFileDescription = result.result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        case .signingDetails:
            signingDetails = result.result
        case .entitlements:
            entitlements = result.result
        case .signatureVerification:
            signatureVerification = result.result
        case .gatekeeperAssessment:
            gatekeeperAssessment = result.result
        case .extendedAttributes:
            extendedAttributes = result.result
        }
    }
}

public enum AppInspectionCommand: CaseIterable, Equatable, Sendable {
    case executableFileDescription
    case signingDetails
    case entitlements
    case signatureVerification
    case gatekeeperAssessment
    case extendedAttributes
}

public struct AppInspectionCommandResult: Equatable, Sendable {
    public let command: AppInspectionCommand
    public let result: CommandResult

    public init(command: AppInspectionCommand, result: CommandResult) {
        self.command = command
        self.result = result
    }
}

public enum GatekeeperStatus: Equatable, Sendable {
    case accepted
    case rejected
    case unknown
}

public enum AppArchitecture: Equatable, Sendable {
    case universal
    case appleSilicon
    case intel64
    case intel32
    case script
    case nonMachO
    case unknown
}

public struct CommandResult: Equatable, Sendable {
    public let command: [String]
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(command: [String], exitCode: Int32, standardOutput: String, standardError: String) {
        self.command = command
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
    }
}

public enum AppInspectionError: Error, Equatable, LocalizedError {
    case notAppBundle(URL)
    case missingInfoPlist(URL)

    public var errorDescription: String? {
        switch self {
        case .notAppBundle(let url):
            return "\(url.path) is not an .app bundle."
        case .missingInfoPlist(let url):
            return "Missing Info.plist at \(url.path)."
        }
    }
}
