import SwiftUI

/// 设置中心统一页面骨架。一级目录和二级目录共用背景、宽度、标题与纵向节奏。
struct AppSettingsPage<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    private var design: AppBackgroundSettings.DesignStyle { AppBackgroundSettingsStore.load().designStyle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: design.isOrnamental ? .serif : .default))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                if design.isOrnamental {
                    VictorianDivider()
                        .frame(maxWidth: .infinity)
                }
                content
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundVisualStyle.pageBackground)
        .navigationTitle(title)
    }
}

/// 设置页统一分组。避免Form在Mac和iPhone上出现完全不同的裸列表外观。
struct AppSettingsCard<Content: View>: View {
    let title: String
    let systemImage: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    private var design: AppBackgroundSettings.DesignStyle { AppBackgroundSettingsStore.load().designStyle }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(design.accent)
                        .frame(width: 26)
                }
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: design.isOrnamental ? .serif : .default))
            }
            if design.isOrnamental {
                VictorianDivider()
            }
            content
        }
        .padding(design.isOrnamental ? 40 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if design.isOrnamental {
                RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.88))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: design.cornerRadius, style: .continuous)
                .fill(design == .apple ? Color.secondary.opacity(0.10) : design.accent.opacity(design == .minimal ? 0.025 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: design.cornerRadius, style: .continuous)
                .stroke(design.border, lineWidth: design.isOrnamental ? 2 : 1)
        )
        .overlay {
            if design.isOrnamental {
                VictorianOrnateFrame()
            }
        }
    }
}

/// 二级设置中的导航行，与一级目录入口保持同一视觉语言。
struct AppSettingsNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: Destination

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 15) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(appHighlightBlue)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AppSettingsDivider: View {
    var body: some View {
        Divider().opacity(0.65)
    }
}

struct AppSettingsStatusMessage: View {
    let message: String

    var body: some View {
        if !message.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(appHighlightBlue)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.09))
            )
        }
    }
}
