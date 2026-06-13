import Foundation

public struct AppInspectionReport: Equatable, Sendable {
    public let bundleURL: URL
    public let bundleName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let executableName: String?
    public let executableURL: URL?
    public let executableFileDescription: String?
    public let signingDetails: CommandResult
    public let entitlements: CommandResult
    public let signatureVerification: CommandResult
    public let gatekeeperAssessment: CommandResult
    public let extendedAttributes: CommandResult

    public init(
        bundleURL: URL,
        bundleName: String,
        bundleIdentifier: String?,
        version: String?,
        executableName: String?,
        executableURL: URL?,
        executableFileDescription: String?,
        signingDetails: CommandResult,
        entitlements: CommandResult,
        signatureVerification: CommandResult,
        gatekeeperAssessment: CommandResult,
        extendedAttributes: CommandResult
    ) {
        self.bundleURL = bundleURL
        self.bundleName = bundleName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.executableName = executableName
        self.executableURL = executableURL
        self.executableFileDescription = executableFileDescription
        self.signingDetails = signingDetails
        self.entitlements = entitlements
        self.signatureVerification = signatureVerification
        self.gatekeeperAssessment = gatekeeperAssessment
        self.extendedAttributes = extendedAttributes
    }

    public var isQuarantined: Bool {
        extendedAttributes.combinedOutput.contains("com.apple.quarantine")
    }

    public var isSignatureValid: Bool {
        signatureVerification.exitCode == 0
    }

    public var architectureSummary: String {
        executableFileDescription ?? "Unknown"
    }
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
