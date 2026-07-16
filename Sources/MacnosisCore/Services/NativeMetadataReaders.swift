import Darwin
import Foundation
import MachO
import Security

public struct ExecutableMetadataReader: Sendable {
    public init() {}

    public func read(bundleURL: URL, executableURL: URL) -> CommandResult? {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let architectures = Bundle(url: bundleURL)?.executableArchitectures,
              architectures.isEmpty == false
        else {
            return nil
        }

        let architectureNames = architectures.map { architectureName(for: $0.int32Value) }
        let format = architectureNames.count > 1 ? "universal" : "thin"
        let output = "\(executableURL.path): Mach-O \(format) executable (\(architectureNames.joined(separator: ", ")))"
        return CommandResult(
            command: ["Foundation.Bundle.executableArchitectures", bundleURL.path],
            exitCode: 0,
            standardOutput: output,
            standardError: "",
            duration: ProcessInfo.processInfo.systemUptime - startedAt
        )
    }

    private func architectureName(for cpuType: Int32) -> String {
        switch cpuType {
        case CPU_TYPE_ARM64:
            return "arm64"
        case CPU_TYPE_X86_64:
            return "x86_64"
        case CPU_TYPE_X86:
            return "i386"
        default:
            return "cpu_type_\(cpuType)"
        }
    }
}

public struct CodeSigningMetadataReader: Sendable {
    private static let adHocSignatureFlag: UInt32 = 0x0002

    public init() {}

    public func read(bundleURL: URL) -> CommandResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let command = ["Security.framework", "SecCodeCopySigningInformation", bundleURL.path]
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return failureResult(
                command: command,
                operation: "SecStaticCodeCreateWithPath",
                status: createStatus,
                startedAt: startedAt
            )
        }

        var rawInformation: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &rawInformation
        )
        guard informationStatus == errSecSuccess,
              let information = rawInformation as? [String: Any]
        else {
            return failureResult(
                command: command,
                operation: "SecCodeCopySigningInformation",
                status: informationStatus,
                startedAt: startedAt
            )
        }

        do {
            let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
            let entitlementData = try PropertyListSerialization.data(
                fromPropertyList: entitlements,
                format: .xml,
                options: 0
            )
            return CommandResult(
                command: command,
                exitCode: 0,
                standardOutput: String(decoding: entitlementData, as: UTF8.self),
                standardError: signingDetails(from: information),
                duration: ProcessInfo.processInfo.systemUptime - startedAt
            )
        } catch {
            return CommandResult(
                command: command,
                exitCode: 1,
                standardOutput: "",
                standardError: "Could not serialize code-signing entitlements: \(error.localizedDescription)",
                duration: ProcessInfo.processInfo.systemUptime - startedAt
            )
        }
    }

    private func signingDetails(from information: [String: Any]) -> String {
        var lines: [String] = []

        if let executableURL = information[kSecCodeInfoMainExecutable as String] as? URL {
            lines.append("Executable=\(executableURL.path)")
        }
        if let identifier = information[kSecCodeInfoIdentifier as String] as? String {
            lines.append("Identifier=\(identifier)")
        }
        if let format = information[kSecCodeInfoFormat as String] as? String {
            lines.append("Format=\(format)")
        }
        if let flags = information[kSecCodeInfoFlags as String] as? NSNumber {
            let rawFlags = flags.uint32Value
            lines.append("CodeDirectory flags=0x\(String(rawFlags, radix: 16))")
            lines.append(
                rawFlags & Self.adHocSignatureFlag == 0
                    ? "Signature=signed"
                    : "Signature=adhoc"
            )
        }
        if let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate] {
            lines.append(contentsOf: certificates.compactMap { certificate in
                guard let summary = SecCertificateCopySubjectSummary(certificate) as String? else {
                    return nil
                }
                return "Authority=\(summary)"
            })
        }

        let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String
        lines.append("TeamIdentifier=\(teamIdentifier ?? "not set")")
        return lines.joined(separator: "\n")
    }

    private func failureResult(
        command: [String],
        operation: String,
        status: OSStatus,
        startedAt: TimeInterval
    ) -> CommandResult {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return CommandResult(
            command: command,
            exitCode: 1,
            standardOutput: "",
            standardError: "\(operation) failed: \(message) (\(status)).",
            duration: ProcessInfo.processInfo.systemUptime - startedAt
        )
    }
}

public struct BundleAttributeReader: Sendable {
    private let outputLimitBytes: Int

    public init(outputLimitBytes: Int = 128 * 1_024) {
        self.outputLimitBytes = max(1, outputLimitBytes)
    }

    public func read(bundleURL: URL) -> CommandResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let command = ["/usr/bin/xattr", "-l", bundleURL.path]

        do {
            let names = try attributeNames(at: bundleURL).sorted()
            let output = names.map { "\(bundleURL.path): \($0)" }.joined(separator: "\n")
            let outputData = Data(output.utf8)
            let wasTruncated = outputData.count > outputLimitBytes
            let capturedData = outputData.prefix(outputLimitBytes)
            let capturedOutput = String(decoding: capturedData, as: UTF8.self)
                + (wasTruncated ? "\n[Output truncated after \(outputLimitBytes) bytes.]" : "")
            return CommandResult(
                command: command,
                exitCode: 0,
                standardOutput: capturedOutput,
                standardError: "",
                standardOutputWasTruncated: wasTruncated,
                duration: ProcessInfo.processInfo.systemUptime - startedAt
            )
        } catch {
            return CommandResult(
                command: command,
                exitCode: 1,
                standardOutput: "",
                standardError: error.localizedDescription,
                duration: ProcessInfo.processInfo.systemUptime - startedAt
            )
        }
    }

    private func attributeNames(at url: URL) throws -> [String] {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw CocoaError(.fileReadInvalidFileName)
            }

            for _ in 0..<3 {
                let requiredSize = listxattr(path, nil, 0, XATTR_NOFOLLOW)
                guard requiredSize >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard requiredSize > 0 else {
                    return []
                }

                var buffer = [CChar](repeating: 0, count: requiredSize)
                let actualSize = buffer.withUnsafeMutableBufferPointer { bufferPointer in
                    listxattr(path, bufferPointer.baseAddress, bufferPointer.count, XATTR_NOFOLLOW)
                }
                if actualSize >= 0 {
                    return buffer.prefix(actualSize)
                        .map { UInt8(bitPattern: $0) }
                        .split(separator: 0)
                        .map { String(decoding: $0, as: UTF8.self) }
                }
                if errno != ERANGE {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }

            throw POSIXError(.ERANGE)
        }
    }
}
