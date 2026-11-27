import Security
import SwiftUI

struct TeachingScheduleConnectionView: View {
    @State private var connection: TeachingScheduleConnection?
    @State private var state: String?
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        AppSettingsPage(title: "排课联动", subtitle: "使用李知本·排课的教师账号授权") {
            AppSettingsCard(title: "账号联动", systemImage: "link") {
                if let connection {
                    if state == "connected" {
                        Label("已通过教师账号授权", systemImage: "link")
                    } else {
                        Text("在排课网或排课 App 的教师设置中打开「授权李知本·授课」，输入下方授权码。")
                        Text(connection.code.uuidString.lowercased()).textSelection(.enabled)
                        Button("检查授权") { perform { try await refresh(connection) } }
                            .disabled(busy)
                    }

                    Button("断开联动", role: .destructive) {
                        perform {
                            try await connection.revoke()
                            try TeachingScheduleConnection.save(nil)
                            self.connection = nil
                            state = nil
                            NotificationCenter.default.post(name: .teachingScheduleConnectionChanged, object: nil)
                        }
                    }
                    .disabled(busy)
                } else {
                    Button("打开联动") {
                        perform {
                            let requested = try await TeachingScheduleConnection.request()
                            try TeachingScheduleConnection.save(requested)
                            connection = requested
                            state = "pending"
                        }
                    }
                    .disabled(busy)
                }

                AppSettingsStatusMessage(message: status)
            }
        }
        .task {
            connection = TeachingScheduleConnection.load()
            if let connection { perform { try await refresh(connection) } }
        }
    }

    private func refresh(_ connection: TeachingScheduleConnection) async throws {
        state = try await connection.status()
        NotificationCenter.default.post(name: .teachingScheduleConnectionChanged, object: nil)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        status = ""
        Task {
            defer { busy = false }
            do {
                try await action()
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

struct TeachingScheduleConnection: Codable {
    let code: UUID
    let secret: String

    private static let endpoint = URL(string: "https://zhibenwang.com/api/auth/teaching-connection/")!
    private static let keychain: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ATeaching.Schedule",
        kSecAttrAccount as String: "connection"
    ]

    static func request() async throws -> Self {
        let data = try await send(to: endpoint, method: "POST")
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func status() async throws -> String {
        struct Result: Decodable {
            let state: String
        }

        let data = try await Self.send(to: resource, method: "GET", secret: secret)
        return try JSONDecoder().decode(Result.self, from: data).state
    }

    func revoke() async throws {
        _ = try await Self.send(to: resource, method: "DELETE", secret: secret)
    }

    var resource: URL {
        Self.endpoint.appendingPathComponent(code.uuidString.lowercased(), isDirectory: true)
    }

    static func load() -> Self? {
        var query = keychain
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func save(_ connection: Self?) throws {
        let result: OSStatus
        if let connection {
            let data = try JSONEncoder().encode(connection)
            let changes = [kSecValueData as String: data]
            let update = SecItemUpdate(keychain as CFDictionary, changes as CFDictionary)
            if update == errSecItemNotFound {
                result = SecItemAdd(keychain.merging(changes) { _, value in value } as CFDictionary, nil)
            } else {
                result = update
            }
        } else {
            let deletion = SecItemDelete(keychain as CFDictionary)
            result = deletion == errSecItemNotFound ? errSecSuccess : deletion
        }

        guard result == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }

    static func send(to url: URL, method: String, secret: String? = nil, body: Data? = nil) async throws -> Data {
        struct Failure: Decodable {
            let detail: String
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let secret { request.setValue(secret, forHTTPHeaderField: "X-Teaching-Connection") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(Failure.self, from: data))?.detail
            throw NSError(domain: "ATeaching.Schedule", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: detail ?? "排课网联动请求失败。"])
        }
        return data
    }
}
