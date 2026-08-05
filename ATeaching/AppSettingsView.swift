import SwiftUI

struct AppSettingsView: View {
    @ViewBuilder
    var body: some View {
        #if os(macOS)
        macSettings
        #else
        mobileSettings
        #endif
    }

    private var mobileSettings: some View {
        List {
            Section {
                NavigationLink {
                    TeachingPDFSettingsView()
                } label: {
                    Label("PDF设置", systemImage: "doc.richtext")
                }
                NavigationLink {
                    AppBackgroundSettingsView()
                } label: {
                    Label("背景设置", systemImage: "paintpalette")
                }
            } header: {
                Text("设置")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                NavigationLink {
                    BackupManagementView()
                } label: {
                    Label("备份管理", systemImage: "externaldrive.badge.icloud")
                }
                NavigationLink {
                    TeachingDebugActionToolsView()
                } label: {
                    Label("功能按键", systemImage: "switch.2")
                }
                NavigationLink {
                    TeachingDebugSettingsView()
                } label: {
                    Label("Debug", systemImage: "ladybug")
                }
            } header: {
                Text("功能")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(AppBackgroundVisualStyle.pageBackground)
    }

    #if os(macOS)
    private var macSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("设置")
                    .font(.system(size: 30, weight: .bold))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        primarySettingsSection
                        functionSettingsSection
                    }
                    VStack(spacing: 18) {
                        primarySettingsSection
                        functionSettingsSection
                    }
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundVisualStyle.pageBackground)
    }

    private var primarySettingsSection: some View {
        macSettingsSection(title: "设置") {
            macSettingsLink(
                title: "PDF设置",
                subtitle: "纸张、边距和NodeMarkdown缩放",
                systemImage: "doc.richtext"
            ) {
                TeachingPDFSettingsView()
            }
            Divider()
            macSettingsLink(
                title: "背景设置",
                subtitle: "管理主界面与表格使用的背景",
                systemImage: "paintpalette"
            ) {
                AppBackgroundSettingsView()
            }
        }
    }

    private var functionSettingsSection: some View {
        macSettingsSection(title: "功能") {
            macSettingsLink(
                title: "备份管理",
                subtitle: "查看和管理应用数据备份",
                systemImage: "externaldrive.badge.icloud"
            ) {
                BackupManagementView()
            }
            Divider()
            macSettingsLink(
                title: "功能按键",
                subtitle: "运行H3查重等维护工具",
                systemImage: "switch.2"
            ) {
                TeachingDebugActionToolsView()
            }
            Divider()
            macSettingsLink(
                title: "Debug",
                subtitle: "开发功能与管线选择",
                systemImage: "ladybug"
            ) {
                TeachingDebugSettingsView()
            }
        }
    }

    private func macSettingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private func macSettingsLink<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(appHighlightBlue)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif
}
