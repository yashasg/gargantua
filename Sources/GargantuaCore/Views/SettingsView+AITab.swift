import SwiftUI

extension SettingsView {

    // MARK: - AI Tab Section Header

    /// Top-level header for the two AI-tab sections ("Your AI engines" and
    /// "What uses which engine"). Rendered at Heading tier so it sits ABOVE the
    /// Title-tier cards it groups, rather than reading as a sub-label.
    func aiSectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
            Text(title)
                .font(GargantuaFonts.sectionHeading)
                .foregroundStyle(GargantuaColors.ink)

            Text(detail)
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, GargantuaSpacing.space4)
    }

    // MARK: - AI Model Section

    var modelSection: some View {
        SettingsSectionContainer(
            "Local AI Engine",
            subtitle: "Toggle between the rule-based template engine and a local MLX model."
        ) {
            enginePreferenceRow

            if useLocalAI {
                Divider()
                    .overlay(GargantuaColors.border)

                modelInfoRow

                if shouldShowMLXDownloadNotice {
                    SettingsNoticeRow(
                        icon: "arrow.down.circle",
                        message: """
                        MLX needs the local model before it can be used. The app will use \
                        template explanations until the download is ready.
                        """,
                        tone: .info
                    )
                }

                if case .downloading(let progress, _) = downloadManager.state {
                    downloadProgressView(progress: progress)
                }

                if case .failed(let message) = downloadManager.state {
                    SettingsNoticeRow(
                        icon: "exclamationmark.triangle.fill",
                        message: message,
                        tone: .protected
                    )
                }

                modelActionRow
            }
        }
    }

    private var modelInfoRow: some View {
        HStack(spacing: GargantuaSpacing.space3) {
            SettingsRowIcon(systemName: "cpu", size: 20)

            SettingsRowText(
                title: downloadManager.modelInfo.name,
                detail: modelStatusText,
                detailColor: modelStatusColor
            )

            Spacer()

            modelSizeLabel
        }
    }

    private func downloadProgressView(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: GargantuaRadius.small)
                        .fill(GargantuaColors.surface3)

                    RoundedRectangle(cornerRadius: GargantuaRadius.small)
                        .fill(GargantuaColors.accent)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(progress * 100))%")
                    .font(GargantuaFonts.monoData)
                    .foregroundStyle(GargantuaColors.ink2)

                Spacer()

                if case .downloading(_, let bytesReceived) = downloadManager.state {
                    Text(ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file))
                        .font(GargantuaFonts.monoData)
                        .foregroundStyle(GargantuaColors.ink3)
                }
            }
        }
    }

    @ViewBuilder
    private var modelActionRow: some View {
        HStack(spacing: GargantuaSpacing.space3) {
            switch downloadManager.state {
            case .notDownloaded, .failed:
                GargantuaButton(
                    "Download Model",
                    icon: "arrow.down.circle.fill",
                    tone: .primary,
                    action: { downloadManager.startDownload() }
                )
                .help("Fetch the local MLX model")

                Text("~\(downloadManager.formattedExpectedSize)")
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink4)

            case .downloading:
                GargantuaButton(
                    "Cancel",
                    icon: "xmark.circle.fill",
                    tone: .ghost(GargantuaColors.protected_),
                    action: { downloadManager.cancelDownload() }
                )

            case .downloaded:
                HStack(spacing: GargantuaSpacing.space2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(GargantuaColors.safe)
                    Text("Ready")
                        .font(GargantuaFonts.label)
                        .foregroundStyle(GargantuaColors.safe)
                }

                Spacer()

                GargantuaButton(
                    "Delete",
                    icon: "trash",
                    tone: .ghost(GargantuaColors.protected_),
                    action: { isShowingDeleteModelConfirm = true }
                )
                .help("Remove the downloaded model from disk")
            }
        }
    }

    private var enginePreferenceRow: some View {
        HStack(alignment: .center, spacing: GargantuaSpacing.space3) {
            SettingsRowIcon(
                systemName: useLocalAI ? "sparkles" : "doc.text",
                size: 16
            )

            SettingsRowText(
                title: "Use local AI",
                detail: useLocalAI
                    ? "On. Generated locally; first run takes longer while shaders compile."
                    : "Off. Instant rule-based explanations from the YAML library."
            )

            Spacer(minLength: GargantuaSpacing.space3)

            Toggle("Use local AI", isOn: useLocalAIBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(useLocalAI ? "Switch to template engine" : "Switch to MLX local engine")
        }
    }

    /// Maps the persisted `AIEnginePreference` to the settings toggle.
    /// Off → Template (instant, rule-based). On → MLX (real local model).
    private var useLocalAI: Bool {
        preferredAIEngine == .mlx
    }

    private var useLocalAIBinding: Binding<Bool> {
        Binding(
            get: { useLocalAI },
            set: { isOn in
                preferredAIEngineRawValue = (isOn ? AIEnginePreference.mlx : .template).rawValue
                // Keep the assignment matrix in sync: if inline "Why?" is
                // pointed at a local engine, follow this Template/MLX switch so
                // the matrix never claims a different local engine than the one
                // actually running.
                if AIEngineAssignments.engine(for: .inlineExplain).isLocal {
                    AIEngineAssignments.set(isOn ? .mlx : .template, for: .inlineExplain)
                }
            }
        )
    }

    private var modelStatusText: String {
        switch downloadManager.state {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading…"
        case .downloaded: "Downloaded"
        case .failed: "Download failed"
        }
    }

    private var modelStatusColor: Color {
        switch downloadManager.state {
        case .notDownloaded: GargantuaColors.ink4
        case .downloading: GargantuaColors.accent
        case .downloaded: GargantuaColors.safe
        case .failed: GargantuaColors.protected_
        }
    }

    private var preferredAIEngine: AIEnginePreference {
        AIEnginePreference(rawValue: preferredAIEngineRawValue) ?? .template
    }

    private var shouldShowMLXDownloadNotice: Bool {
        guard preferredAIEngine == .mlx else { return false }
        if case .downloaded = downloadManager.state { return false }
        return true
    }

    private var modelSizeLabel: some View {
        Group {
            if let size = downloadManager.formattedDownloadedSize {
                Text(size)
                    .font(GargantuaFonts.monoData)
                    .foregroundStyle(GargantuaColors.ink2)
            } else {
                Text(downloadManager.formattedExpectedSize)
                    .font(GargantuaFonts.monoData)
                    .foregroundStyle(GargantuaColors.ink4)
            }
        }
    }
}
