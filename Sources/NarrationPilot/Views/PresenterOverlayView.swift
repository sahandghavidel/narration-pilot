import SwiftUI

struct PresenterOverlayView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            sceneColumn(title: "Previous", text: appModel.previousSceneDisplayText, isCurrent: false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(appModel.scriptSceneProgress)
                        .font(.caption.bold())
                        .foregroundStyle(appModel.presenterOverlaySecondaryTextColor.opacity(appModel.presenterOverlaySecondaryTextOpacity))

                    Spacer()

                    Button {
                        appModel.openCurrentSceneEditor()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text(appModel.scriptInputFormat.usesStructuredScenes ? "View Scene" : "Edit Scene")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .foregroundStyle(appModel.presenterOverlayCurrentTextColor.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .overlay(
                                Capsule()
                                    .stroke(appModel.presenterOverlayCurrentTextColor.opacity(0.35))
                            )
                    )
                    .help(appModel.scriptInputFormat.usesStructuredScenes ? "View current scene" : "Edit current scene")
                    .disabled(appModel.currentSceneText == nil)
                }

                if let title = appModel.currentSceneTitle {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(appModel.presenterOverlaySecondaryTextColor.opacity(appModel.presenterOverlaySecondaryTextOpacity))
                }

                if let onScreen = appModel.currentSceneOnScreenSummary {
                    Text("On screen: \(onScreen)")
                        .font(.system(size: CGFloat(appModel.presenterOverlaySideFontSize), weight: .medium))
                        .foregroundStyle(appModel.presenterOverlaySecondaryTextColor.opacity(appModel.presenterOverlaySecondaryTextOpacity))
                        .lineLimit(2)
                }

                if let code = appModel.currentSceneCodeSummary {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CODE")
                            .font(.caption2.bold())
                            .foregroundStyle(appModel.presenterOverlaySecondaryTextColor.opacity(appModel.presenterOverlaySecondaryTextOpacity))
                        Text(code)
                            .font(.system(
                                size: CGFloat(appModel.presenterOverlaySideFontSize),
                                design: .monospaced
                            ))
                            .foregroundStyle(appModel.presenterOverlayCurrentTextColor.opacity(appModel.presenterOverlayCurrentTextOpacity))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.24))
                    )
                }

                Text(appModel.currentSceneText ?? "Paste a script and turn on Script mode.")
                    .font(.system(size: CGFloat(appModel.presenterOverlayCurrentFontSize), weight: .semibold))
                    .foregroundStyle(appModel.presenterOverlayCurrentTextColor.opacity(appModel.presenterOverlayCurrentTextOpacity))
                    .lineLimit(nil)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)

            sceneColumn(title: "Next", text: appModel.nextSceneDisplayText, isCurrent: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(appModel.presenterOverlayOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(appModel.presenterOverlayCurrentTextColor.opacity(0.16))
        )
    }

    private func sceneColumn(title: String, text: String?, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(appModel.presenterOverlaySecondaryTextColor.opacity(appModel.presenterOverlaySecondaryTextOpacity * 0.7))

            Text(text ?? "None")
                .font(.system(size: CGFloat(appModel.presenterOverlaySideFontSize)))
                .foregroundStyle(appModel.presenterOverlaySecondaryTextColor.opacity(text == nil ? appModel.presenterOverlaySecondaryTextOpacity * 0.45 : appModel.presenterOverlaySecondaryTextOpacity))
                .lineLimit(nil)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CGFloat(appModel.presenterOverlaySideColumnWidth))
    }
}
