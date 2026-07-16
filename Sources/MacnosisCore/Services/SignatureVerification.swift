import Foundation
import Security

public struct SignatureVerificationReader: Sendable {
    private static let helperName = "MacnosisSecurityHelper"

    private let helperURL: URL?
    private let timeout: TimeInterval

    public init(helperURL: URL? = nil, timeout: TimeInterval = 45) {
        self.helperURL = helperURL
        self.timeout = max(0, timeout)
    }

    public func read(bundleURL: URL, commandExecutor: CommandExecutor) -> CommandResult {
        if let helperURL = helperURL ?? Self.bundledHelperURL() {
            let helperResult = commandExecutor.run(
                [helperURL.path, "verify", bundleURL.path],
                timeout: timeout
            )
            if helperResult.succeeded {
                return helperResult
            }

            switch helperResult.termination {
            case .timedOut, .cancelled:
                return helperResult
            case .exited, .failedToLaunch:
                let remainingTimeout = max(0, timeout - (helperResult.duration ?? 0))
                let fallbackResult = runCodesign(
                    bundleURL: bundleURL,
                    commandExecutor: commandExecutor,
                    timeout: remainingTimeout
                )
                return fallbackResult.addingDuration(helperResult.duration)
            }
        }

        return runCodesign(
            bundleURL: bundleURL,
            commandExecutor: commandExecutor,
            timeout: timeout
        )
    }

    private func runCodesign(
        bundleURL: URL,
        commandExecutor: CommandExecutor,
        timeout: TimeInterval
    ) -> CommandResult {
        commandExecutor.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", bundleURL.path],
            timeout: timeout
        )
    }

    private static func bundledHelperURL() -> URL? {
        let candidate = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers", directoryHint: .isDirectory)
            .appending(path: helperName, directoryHint: .notDirectory)
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }
}

public struct StaticCodeSignatureValidator: Sendable {
    public init() {}

    public func validate(bundleURL: URL) -> CommandResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let command = ["Security.framework", "SecStaticCodeCheckValidityWithErrors", bundleURL.path]
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return failureResult(
                command: command,
                operation: "SecStaticCodeCreateWithPath",
                status: createStatus,
                error: nil,
                startedAt: startedAt
            )
        }

        let flags = SecCSFlags(rawValue:
            kSecCSCheckAllArchitectures
                | kSecCSCheckNestedCode
                | kSecCSStrictValidate
        )
        var unmanagedValidationError: Unmanaged<CFError>?
        let validationStatus = SecStaticCodeCheckValidityWithErrors(
            staticCode,
            flags,
            nil,
            &unmanagedValidationError
        )
        let validationError = unmanagedValidationError?.takeRetainedValue()

        guard validationStatus == errSecSuccess else {
            return failureResult(
                command: command,
                operation: "SecStaticCodeCheckValidityWithErrors",
                status: validationStatus,
                error: validationError,
                startedAt: startedAt
            )
        }

        return CommandResult(
            command: command,
            exitCode: 0,
            standardOutput: "Security.framework deep signature validation succeeded.",
            standardError: "",
            duration: elapsed(since: startedAt)
        )
    }

    private func failureResult(
        command: [String],
        operation: String,
        status: OSStatus,
        error: CFError?,
        startedAt: TimeInterval
    ) -> CommandResult {
        let statusMessage = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        let target = command.last ?? "Code object"
        var messages = ["\(target): \(operation) failed: \(statusMessage) (\(status))."]
        if let error {
            let description = CFErrorCopyDescription(error) as String
            if description.isEmpty == false, messages.contains(description) == false {
                messages.append(description)
            }
        }

        return CommandResult(
            command: command,
            exitCode: 1,
            standardOutput: "",
            standardError: messages.joined(separator: "\n"),
            duration: elapsed(since: startedAt)
        )
    }

    private func elapsed(since startedAt: TimeInterval) -> TimeInterval {
        ProcessInfo.processInfo.systemUptime - startedAt
    }
}

private extension CommandResult {
    func addingDuration(_ previousDuration: TimeInterval?) -> CommandResult {
        CommandResult(
            command: command,
            termination: termination,
            standardOutput: standardOutput,
            standardError: standardError,
            standardOutputWasTruncated: standardOutputWasTruncated,
            standardErrorWasTruncated: standardErrorWasTruncated,
            duration: (previousDuration ?? 0) + (duration ?? 0)
        )
    }
}
