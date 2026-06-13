import MacnosisCore
import SwiftUI
import UniformTypeIdentifiers

struct MacnosisContentView: View {
    @ObservedObject var model: MacnosisAppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(MacnosisTheme.background)
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: model.appImportTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.inspect(url)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Macnosis")
                    .font(.system(size: 24, weight: .semibold))
                Text("Diagnose and repair macOS app bundles.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.chooseApp()
            } label: {
                Label("Inspect App", systemImage: "app.badge.checkmark")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        if model.isInspecting {
            ProgressView("Inspecting app bundle...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let report = model.report {
            InspectionReportView(report: report)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "stethoscope")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(MacnosisTheme.accent)

            Text("Drop into a diagnosis.")
                .font(.system(size: 22, weight: .semibold))

            Text(model.errorMessage ?? "Choose a macOS .app bundle to inspect signing, quarantine, architecture, and Gatekeeper state.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button {
                model.chooseApp()
            } label: {
                Label("Choose App", systemImage: "folder")
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct InspectionReportView: View {
    let report: AppInspectionReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                detailGrid
                commandSection("Code Signing", result: report.signingDetails)
                commandSection("Entitlements", result: report.entitlements)
                commandSection("Strict Verification", result: report.signatureVerification)
                commandSection("Gatekeeper", result: report.gatekeeperAssessment)
                commandSection("Extended Attributes", result: report.extendedAttributes)
            }
            .padding(24)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.bundleName)
                    .font(.system(size: 26, weight: .semibold))
                Spacer()
                statusBadge(report.isSignatureValid ? "Signature Valid" : "Signature Issue", isGood: report.isSignatureValid)
                statusBadge(report.isQuarantined ? "Quarantined" : "No Quarantine", isGood: report.isQuarantined == false)
            }

            Text(report.bundleURL.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 22, verticalSpacing: 10) {
            detailRow("Bundle ID", report.bundleIdentifier ?? "Unknown")
            detailRow("Version", report.version ?? "Unknown")
            detailRow("Executable", report.executableName ?? "Unknown")
            detailRow("Architecture", report.architectureSummary)
        }
        .font(.system(size: 13))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func commandSection(_ title: String, result: CommandResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("exit \(result.exitCode)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(result.exitCode == 0 ? MacnosisTheme.good : MacnosisTheme.warning)
            }

            Text(result.combinedOutput.isEmpty ? "No output." : result.combinedOutput)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacnosisTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func statusBadge(_ text: String, isGood: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isGood ? MacnosisTheme.good : MacnosisTheme.warning)
    }
}
