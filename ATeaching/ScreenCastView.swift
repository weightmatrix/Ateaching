import SwiftUI

struct ScreenCastView: View {
    @ObservedObject var service: ScreenCastService
    @AppStorage("ScreenCast.displayName") private var displayName = ""
    @AppStorage("ScreenCast.lastReceivePIN") private var lastReceivePIN = ""
    @State private var pendingPIN = ""
    @State private var pinAction: PINAction?

    private enum PINAction: String, Identifiable {
        case cast
        case receive
        case changeCast
        case reconnect

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("投屏")
                        .font(.title.bold())
                    TextField("填写你的名字", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    if cleanName.isEmpty {
                        Text("填写名字后才可以使用投屏功能")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                actionBand
                statusPanel
            }
            .frame(maxWidth: 760)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .alert(pinTitle, isPresented: pinAlertBinding) {
            TextField("四位数字", text: $pendingPIN)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: pendingPIN) { _, value in
                    let normalized = ScreenCastService.normalizedPIN(value)
                    if normalized != value { pendingPIN = normalized }
                }
            Button("确认") { performPINAction() }
                .disabled(ScreenCastService.normalizedPIN(pendingPIN).count != 4)
            Button("取消", role: .cancel) { pinAction = nil }
        } message: {
            Text("同一 Wi-Fi 内，四位数字相同的设备会自动匹配。")
        }
        .onAppear {
            ScreenCastDiagnostic40.record(
                "投屏页出现 isCasting=\(service.isCasting) isReceiving=\(service.isReceiving) status=\(service.statusMessage)",
                instanceID: service.diagnosticID
            )
        }
        .onDisappear {
            ScreenCastDiagnostic40.record(
                "投屏页离开 isCasting=\(service.isCasting) isReceiving=\(service.isReceiving) status=\(service.statusMessage)",
                instanceID: service.diagnosticID
            )
        }
    }

    private var actionBand: some View {
        HStack(spacing: 12) {
            actionButton(
                title: "投屏",
                icon: "arrow.up.forward",
                active: service.isCasting
            ) {
                if service.isCasting {
                    service.stopAll(reason: "用户点击停止投屏")
                } else {
                    pendingPIN = ScreenCastService.randomPIN()
                    pinAction = .cast
                    ScreenCastDiagnostic40.record(
                        "用户点击投屏，打开四位数字确认 pendingPIN=\(pendingPIN)",
                        instanceID: service.diagnosticID
                    )
                }
            }

            actionButton(
                title: "接收",
                icon: "arrow.down.forward",
                active: service.isReceiving
            ) {
                if service.isReceiving {
                    service.stopAll(reason: "用户点击停止接收")
                } else {
                    pendingPIN = lastReceivePIN
                    pinAction = .receive
                }
            }
        }
        .disabled(cleanName.isEmpty)
    }

    private func actionButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: active ? "stop.fill" : icon)
                    .font(.title2)
                Text(active ? "停止\(title)" : title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? .red : .blue)
    }

    @ViewBuilder
    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("投屏状态", systemImage: statusIcon)
                    .font(.headline)
                Spacer()
                Text(service.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if service.isCasting || service.isReceiving {
                Divider()
                HStack {
                    Text("四位数字")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(service.pin)
                        .font(.title2.monospacedDigit().bold())
                    Button {
                        pendingPIN = service.pin
                        pinAction = service.isCasting ? .changeCast : .reconnect
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("更改四位数字")
                }
            }

            if service.isCasting {
                channelControls
            }

            if service.isReceiving, service.isConnected {
                HStack {
                    Text("主控")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(service.hostName)
                }
            }

            if service.members.isEmpty == false {
                Divider()
                Text("成员与批注颜色")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(service.members) { member in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.screenCast(hex: member.colorHex))
                                .frame(width: 12, height: 12)
                            Text(member.name)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var channelControls: some View {
        HStack(spacing: 10) {
            ForEach(ScreenCastContentKind.allCases) { kind in
                Toggle(isOn: channelBinding(kind)) {
                    Label(kind.title, systemImage: kind.systemImage)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(service.enabledKinds.contains(kind) ? .blue : .secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func channelBinding(_ kind: ScreenCastContentKind) -> Binding<Bool> {
        Binding(
            get: { service.enabledKinds.contains(kind) },
            set: { enabled in
                var value = service.enabledKinds
                if enabled { value.insert(kind) } else { value.remove(kind) }
                service.enabledKinds = value
            }
        )
    }

    private var statusIcon: String {
        if service.isCasting { return "arrow.up.forward.circle.fill" }
        if service.isReceiving { return "arrow.down.forward.circle.fill" }
        return "circle.dashed"
    }

    private var cleanName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pinAlertBinding: Binding<Bool> {
        Binding(get: { pinAction != nil }, set: { if !$0 { pinAction = nil } })
    }

    private var pinTitle: String {
        switch pinAction {
        case .cast: "设置投屏四位数字"
        case .receive: "输入主控四位数字"
        case .changeCast, .reconnect: "更改四位数字"
        case nil: "四位数字"
        }
    }

    private func performPINAction() {
        let normalized = ScreenCastService.normalizedPIN(pendingPIN)
        ScreenCastDiagnostic40.record(
            "确认四位数字 action=\(pinAction?.rawValue ?? "nil") pin=\(normalized) nameEmpty=\(cleanName.isEmpty)",
            instanceID: service.diagnosticID
        )
        guard normalized.count == 4 else {
            ScreenCastDiagnostic40.record("确认被拒绝：PIN不是四位", instanceID: service.diagnosticID)
            return
        }
        switch pinAction {
        case .cast:
            service.startCasting(pin: normalized, name: cleanName)
        case .receive:
            lastReceivePIN = normalized
            service.startReceiving(pin: normalized, name: cleanName)
        case .changeCast:
            service.changeCastingPIN(normalized)
        case .reconnect:
            lastReceivePIN = normalized
            service.reconnect(with: normalized)
        case nil:
            break
        }
        ScreenCastDiagnostic40.record(
            "确认动作返回 isCasting=\(service.isCasting) isReceiving=\(service.isReceiving) status=\(service.statusMessage)",
            instanceID: service.diagnosticID
        )
        pinAction = nil
    }
}

extension Color {
    static func screenCast(hex: String) -> Color {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return .blue }
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
