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
    public var executableFileDescriptionResult: CommandResult?
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
        executableFileDescriptionResult: CommandResult? = nil,
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
        self.executableFileDescriptionResult = executableFileDescriptionResult
        self.signingDetails = signingDetails
        self.entitlements = entitlements
        self.signatureVerification = signatureVerification
        self.gatekeeperAssessment = gatekeeperAssessment
        self.extendedAttributes = extendedAttributes
    }

    public var hasExecutableFileDescription: Bool {
        executableFileDescriptionAvailability == .available
    }

    public var hasSigningDetails: Bool {
        signingDetailsAvailability == .available
    }

    public var hasEntitlements: Bool {
        debuggingStatus == .debuggable || debuggingStatus == .notDebuggable
    }

    public var hasSignatureVerification: Bool {
        signatureVerificationStatus == .valid || signatureVerificationStatus == .invalid
    }

    public var hasGatekeeperAssessment: Bool {
        switch gatekeeperStatus {
        case .accepted, .rejected, .unknown:
            return true
        case .pending, .unavailable:
            return false
        }
    }

    public var hasExtendedAttributes: Bool {
        quarantineStatus == .quarantined || quarantineStatus == .clear
    }

    public var isFullyInspected: Bool {
        let executableIsResolved = executableURL == nil
            || executableFileDescription != nil
            || executableFileDescriptionResult != nil
        return executableIsResolved
            && signingDetails != nil
            && entitlements != nil
            && signatureVerification != nil
            && gatekeeperAssessment != nil
            && extendedAttributes != nil
    }

    public var isQuarantined: Bool {
        quarantineStatus == .quarantined
    }

    public var isSignatureValid: Bool {
        signatureVerificationStatus == .valid
    }

    public var gatekeeperStatus: GatekeeperStatus {
        guard let gatekeeperAssessment else {
            return .pending
        }

        guard gatekeeperAssessment.didExit else {
            return .unavailable
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
        guard let signingDetails else {
            return false
        }

        let output = signingDetails.combinedOutput
        if output.contains("Signature=adhoc") {
            return true
        }
        if output.contains("Signature=signed") {
            return false
        }

        return output.contains("TeamIdentifier=not set") && signingAuthorityChain.isEmpty
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
        debuggingStatus == .debuggable
    }

    public var executableFileDescriptionAvailability: DiagnosticAvailability {
        if executableFileDescription != nil {
            return .available
        }

        guard let executableFileDescriptionResult else {
            return .pending
        }

        return executableFileDescriptionResult.succeeded ? .available : .unavailable
    }

    public var signingDetailsAvailability: DiagnosticAvailability {
        guard let signingDetails else {
            return .pending
        }

        guard signingDetails.didExit,
              signingDetails.standardOutputWasTruncated == false,
              signingDetails.standardErrorWasTruncated == false
        else {
            return .unavailable
        }

        return .available
    }

    public var signatureVerificationStatus: SignatureVerificationStatus {
        guard let signatureVerification else {
            return .pending
        }

        guard signatureVerification.didExit else {
            return .unavailable
        }

        return signatureVerification.succeeded ? .valid : .invalid
    }

    public var quarantineStatus: QuarantineStatus {
        guard let extendedAttributes else {
            return .pending
        }

        guard extendedAttributes.succeeded else {
            return .unavailable
        }

        if extendedAttributes.combinedOutput.contains("com.apple.quarantine") {
            return .quarantined
        }

        return extendedAttributes.standardOutputWasTruncated || extendedAttributes.standardErrorWasTruncated
            ? .unavailable
            : .clear
    }

    public var debuggingStatus: DebuggabilityStatus {
        guard let entitlements else {
            return .pending
        }

        guard entitlements.succeeded,
              entitlements.standardOutputWasTruncated == false,
              entitlements.standardErrorWasTruncated == false
        else {
            return .unavailable
        }

        let output = entitlements.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.isEmpty == false else {
            return .notDebuggable
        }

        guard let entitlementDictionary = propertyListDictionary(from: output) else {
            return .malformed
        }

        return entitlementDictionary["com.apple.security.get-task-allow"] as? Bool == true
            ? .debuggable
            : .notDebuggable
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

    private func propertyListDictionary(from output: String) -> [String: Any]? {
        guard let data = output.data(using: .utf8),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else {
            return nil
        }

        return propertyList as? [String: Any]
    }

    public mutating func apply(_ result: AppInspectionCommandResult) {
        switch result.command {
        case .executableFileDescription:
            executableFileDescriptionResult = result.result
            executableFileDescription = result.result.succeeded
                ? result.result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        case .signingMetadata:
            signingDetails = result.result.selectingOutput(standardOutput: false, standardError: true)
            entitlements = result.result.selectingOutput(
                standardOutput: true,
                standardError: result.result.succeeded == false
            )
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
    case signingMetadata
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
    case pending
    case accepted
    case rejected
    case unknown
    case unavailable
}

public enum DiagnosticAvailability: Equatable, Sendable {
    case pending
    case available
    case unavailable
}

public enum SignatureVerificationStatus: Equatable, Sendable {
    case pending
    case valid
    case invalid
    case unavailable
}

public enum QuarantineStatus: Equatable, Sendable {
    case pending
    case quarantined
    case clear
    case unavailable
}

public enum DebuggabilityStatus: Equatable, Sendable {
    case pending
    case debuggable
    case notDebuggable
    case malformed
    case unavailable
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

public enum CommandTermination: Equatable, Sendable {
    case exited(Int32)
    case timedOut(seconds: Int)
    case cancelled
    case failedToLaunch
}

public struct CommandResult: Equatable, Sendable {
    public let command: [String]
    public let termination: CommandTermination
    public let standardOutput: String
    public let standardError: String
    public let standardOutputWasTruncated: Bool
    public let standardErrorWasTruncated: Bool
    public let duration: TimeInterval?

    public init(
        command: [String],
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        standardOutputWasTruncated: Bool = false,
        standardErrorWasTruncated: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.init(
            command: command,
            termination: .exited(exitCode),
            standardOutput: standardOutput,
            standardError: standardError,
            standardOutputWasTruncated: standardOutputWasTruncated,
            standardErrorWasTruncated: standardErrorWasTruncated,
            duration: duration
        )
    }

    public init(
        command: [String],
        termination: CommandTermination,
        standardOutput: String,
        standardError: String,
        standardOutputWasTruncated: Bool = false,
        standardErrorWasTruncated: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.command = command
        self.termination = termination
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.standardOutputWasTruncated = standardOutputWasTruncated
        self.standardErrorWasTruncated = standardErrorWasTruncated
        self.duration = duration
    }

    public var exitCode: Int32 {
        switch termination {
        case .exited(let exitCode):
            return exitCode
        case .timedOut:
            return 124
        case .cancelled:
            return 130
        case .failedToLaunch:
            return 127
        }
    }

    public var didExit: Bool {
        if case .exited = termination {
            return true
        }

        return false
    }

    public var succeeded: Bool {
        termination == .exited(0)
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
    }

    fileprivate func selectingOutput(
        standardOutput includeStandardOutput: Bool,
        standardError includeStandardError: Bool
    ) -> CommandResult {
        CommandResult(
            command: command,
            termination: termination,
            standardOutput: includeStandardOutput ? standardOutput : "",
            standardError: includeStandardError ? standardError : "",
            standardOutputWasTruncated: includeStandardOutput && standardOutputWasTruncated,
            standardErrorWasTruncated: includeStandardError && standardErrorWasTruncated,
            duration: duration
        )
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
