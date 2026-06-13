import MacnosisCore
import SwiftUI

struct MacnosisContentView: View {
    @ObservedObject var model: MacnosisAppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspace
        }
        .background(MacnosisTheme.background)
        .dropDestination(for: URL.self) { urls, _ in
            model.inspect(urls)
            return urls.contains { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame }
        } isTargeted: { isTargeted in
            model.isDropTargeted = isTargeted
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

            ToolbarIconButton(
                symbol: "folder.badge.plus",
                label: "Inspect Apps",
                action: model.chooseApp
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var workspace: some View {
        HStack(spacing: 0) {
            if model.inspectedApps.isEmpty == false {
                inspectedAppsSidebar
                Divider()
            }

            detailPane
        }
    }

    private var inspectedAppsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspected Apps")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.inspectedApps) { app in
                        InspectedAppRow(
                            app: app,
                            isSelected: model.selectedAppID == app.id,
                            select: { model.selectApp(id: app.id) },
                            close: { model.closeApp(id: app.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 250)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let app = model.selectedApp {
            if app.isInspecting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Inspecting \(app.displayName)...")
                        .font(.system(size: 14, weight: .medium))
                    Text(app.url.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = app.report {
                InspectionReportView(report: report)
            } else {
                AppDropZone(
                    title: app.errorMessage ?? "Inspection blocked.",
                    message: "Drop more macOS .app bundles here, or choose one or more from the toolbar.",
                    isTargeted: model.isDropTargeted,
                    chooseApp: { model.chooseApp() }
                )
            }
        } else {
            AppDropZone(
                title: "Drop into a diagnosis.",
                message: "Choose or drop one or more macOS .app bundles to inspect signing, quarantine, architecture, and Gatekeeper state.",
                isTargeted: model.isDropTargeted,
                chooseApp: { model.chooseApp() }
            )
        }
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 22, height: 22)
            .frame(width: 34, height: 30)
            .background(isHovered ? MacnosisTheme.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .help(label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct InspectedAppRow: View {
    let app: InspectedApp
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(url: app.url, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: statusImage)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(statusColor)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1)
                        }
                        .offset(x: 3, y: 3)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(app.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if app.isInspecting {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close \(app.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(isSelected ? MacnosisTheme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: select)
    }

    private var statusImage: String {
        if app.isInspecting {
            return "clock"
        }

        return app.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if app.isInspecting {
            return MacnosisTheme.accent
        }

        return app.hasWarning ? MacnosisTheme.warning : MacnosisTheme.good
    }
}

private struct AppDropZone: View {
    let title: String
    let message: String
    let isTargeted: Bool
    let chooseApp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: isTargeted ? "arrow.down.app.fill" : "stethoscope")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(isTargeted ? MacnosisTheme.good : MacnosisTheme.accent)

                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                Button {
                    chooseApp()
                } label: {
                    Label("Choose Apps", systemImage: "folder")
                }
                .controlSize(.large)
                .padding(.top, 2)
            }
            .padding(28)
            .frame(maxWidth: 560)
            .background(MacnosisTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isTargeted ? MacnosisTheme.good : MacnosisTheme.border, style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [7, 5]))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                CommandSection(title: "Code Signing", result: report.signingDetails)
                    .id(report.bundleURL.path + "-signing")
                CommandSection(title: "Entitlements", result: report.entitlements)
                    .id(report.bundleURL.path + "-entitlements")
                CommandSection(title: "Strict Verification", result: report.signatureVerification)
                    .id(report.bundleURL.path + "-verification")
                CommandSection(title: "Gatekeeper", result: report.gatekeeperAssessment)
                    .id(report.bundleURL.path + "-gatekeeper")
                CommandSection(title: "Extended Attributes", result: report.extendedAttributes)
                    .id(report.bundleURL.path + "-attributes")
            }
            .padding(24)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                AppIconView(url: report.bundleURL, size: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(packageName)
                        .font(.system(size: 26, weight: .semibold))

                    Text(report.bundleURL.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
                statusBadge(report.isSignatureValid ? "Signature Valid" : "Signature Issue", isGood: report.isSignatureValid)
                statusBadge(report.isQuarantined ? "Quarantined" : "No Quarantine", isGood: report.isQuarantined == false)
            }
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 22, verticalSpacing: 10) {
            detailRow("Bundle ID", report.bundleIdentifier ?? "Unknown")
            if report.bundleName != packageName {
                detailRow("Bundle Name", report.bundleName)
            }
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

    private func statusBadge(_ text: String, isGood: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isGood ? MacnosisTheme.good : MacnosisTheme.warning)
    }

    private var packageName: String {
        report.bundleURL.deletingPathExtension().lastPathComponent
    }
}

private struct CommandSection: View {
    let title: String
    let result: CommandResult

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("exit \(result.exitCode)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(result.exitCode == 0 ? MacnosisTheme.good : MacnosisTheme.warning)
            }

            Text(visibleOutput)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 8)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacnosisTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if canExpand {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "Show Less" : "Show Full Output", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Collapse command output." : "Expand the complete command output.")
            }
        }
    }

    private var visibleOutput: String {
        let output = fullOutput
        guard isExpanded == false else {
            return output
        }

        return outputPreview(output)
    }

    private var fullOutput: String {
        result.combinedOutput.isEmpty ? "No output." : result.combinedOutput
    }

    private var canExpand: Bool {
        fullOutput.count > maxPreviewCharacters
    }

    private func outputPreview(_ output: String) -> String {
        guard output.count > maxPreviewCharacters else {
            return output
        }

        let preview = String(output.prefix(maxPreviewCharacters))
        return preview + "\n..."
    }

    private var maxPreviewCharacters: Int {
        1600
    }
}
