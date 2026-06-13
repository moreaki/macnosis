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

    public var gatekeeperStatus: GatekeeperStatus {
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
        signingDetails.combinedOutput.contains("Signature=adhoc")
            || signingDetails.combinedOutput.contains("TeamIdentifier=not set")
    }

    public var hasDeveloperIDSignature: Bool {
        signingDetails.combinedOutput.contains("Authority=Developer ID Application")
    }

    public var isDebuggable: Bool {
        entitlements.combinedOutput.contains("com.apple.security.get-task-allow")
    }

    public var architectureSummary: String {
        executableFileDescription ?? "Unknown"
    }

    public var architectures: [AppArchitecture] {
        let output = architectureSummary.lowercased()
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

        return architectures.isEmpty ? [.unknown] : architectures
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
