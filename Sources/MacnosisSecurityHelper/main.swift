import Darwin
import Foundation
import MacnosisCore

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "verify" else {
    write("Usage: MacnosisSecurityHelper verify <app-bundle>\n", to: .standardError)
    exit(EX_USAGE)
}

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[2])
let result = StaticCodeSignatureValidator().validate(bundleURL: bundleURL)
write(result.standardOutput, to: .standardOutput)
write(result.standardError, to: .standardError)
exit(result.succeeded ? EXIT_SUCCESS : EXIT_FAILURE)

private func write(_ output: String, to handle: FileHandle) {
    guard output.isEmpty == false else {
        return
    }

    let terminatedOutput = output.hasSuffix("\n") ? output : output + "\n"
    try? handle.write(contentsOf: Data(terminatedOutput.utf8))
}
