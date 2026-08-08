import SwiftUI

struct ScreenCastView: View {
    @ObservedObject var service: ScreenCastService
    @State private var showInternalCast = false
    @State private var receiveIP = ""
    @State private var receivePort = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("投屏")
                .font(.title2.weight(.semibold))

            HStack(spacing: 20) {
                Button {
                    showInternalCast = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.connected.to.line.below")
                            .font(.system(size: 28))
                        Text("APP内投屏")
                            .font(.headline)
                    }
                    .frame(width: 140, height: 100)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // 网络投屏 - 待开发
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 28))
                        Text("网络投屏")
                            .font(.headline)
                        Text("待开发")
                            .font(.caption2)
                    }
                    .frame(width: 140, height: 100)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("投屏状态")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Group {
                    statusRow("主控 IP", service.isCasting ? service.localIP : (service.isReceiving ? service.connectedHost : "--"))
                    statusRow("端口", service.isCasting || service.isReceiving ? "\(service.port)" : "--")
                    statusRow("状态", statusText)
                    if service.isReceiving, let studentName = service.receivedStudentName {
                        statusRow("接收学生", studentName)
                    }
                }
                .font(.callout.monospaced())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))

            if service.isReceiving, let document = service.receivedDocument {
                Divider()
                ScreenCastReceiverView(document: document, service: service)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 400)
        .sheet(isPresented: $showInternalCast) {
            InternalCastSheet(service: service, receiveIP: $receiveIP, receivePort: $receivePort)
        }
    }

    private var statusText: String {
        if service.isCasting { return "投屏中" }
        if service.isReceiving { return "接收中" }
        return "未连接"
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

private struct InternalCastSheet: View {
    @ObservedObject var service: ScreenCastService
    @Binding var receiveIP: String
    @Binding var receivePort: String
    @Environment(\.dismiss) private var dismiss
    @State private var showCastControls = false
    @State private var showReceiveControls = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if !showCastControls && !showReceiveControls {
                    HStack(spacing: 24) {
                        Button {
                            showCastControls = true
                            service.startCasting()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 24))
                                Text("投屏")
                                    .font(.headline)
                            }
                            .frame(width: 120, height: 90)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(service.isReceiving)

                        Button {
                            showReceiveControls = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.forward")
                                    .font(.system(size: 24))
                                Text("接收")
                                    .font(.headline)
                            }
                            .frame(width: 120, height: 90)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(service.isCasting)
                    }
                }

                if showCastControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("投屏服务已启动")
                            .font(.headline)
                        Text("IP: \(service.localIP)")
                            .font(.callout.monospaced())
                        Text("端口: \(service.port)")
                            .font(.callout.monospaced())
                        Text("等待接收端连接...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if service.isCasting {
                            Button("停止投屏") {
                                service.stopCasting()
                                showCastControls = false
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
                }

                if showReceiveControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("连接投屏端")
                            .font(.headline)
                        HStack {
                            Text("IP:")
                                .frame(width: 30, alignment: .leading)
                            TextField("192.168.1.x", text: $receiveIP)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }
                        HStack {
                            Text("端口:")
                                .frame(width: 30, alignment: .leading)
                            TextField("55555", text: $receivePort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        HStack(spacing: 12) {
                            Button("连接") {
                                if let port = UInt16(receivePort) {
                                    service.startReceiving(host: receiveIP, port: port)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(receiveIP.isEmpty || receivePort.isEmpty)

                            if service.isReceiving {
                                Button("断开") {
                                    service.stopReceiving()
                                    showReceiveControls = false
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                        if !service.statusMessage.isEmpty {
                            Text(service.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("APP内投屏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 420, height: 440)
    }
}
