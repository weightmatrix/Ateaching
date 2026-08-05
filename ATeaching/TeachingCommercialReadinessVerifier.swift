import CryptoKit
import Foundation

struct TeachingCommercialReadinessReport: Hashable {
    var totalChecks: Int
    var warningCount: Int
    var errorCount: Int
    var messages: [String]

    var isPassed: Bool {
        errorCount == 0
    }
}

struct TeachingCommercialPreflightResult: Hashable {
    var blockingErrors: [String]
    var warnings: [String]

    var canProceed: Bool {
        blockingErrors.isEmpty
    }
}

enum TeachingCommercialReadinessVerifier {
    static func preflight(
        students: [TeachingStudentItem],
        requireSyncPath: Bool
    ) -> TeachingCommercialPreflightResult {
        var blockingErrors: [String] = []
        var warnings: [String] = []

        let defaults: TeachingStudentSystemSettings
        do {
            _ = try TeachingStudentSettingsStore.loadSnapshot()
            defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
        } catch {
            return TeachingCommercialPreflightResult(
                blockingErrors: ["设置读取失败：\(error.localizedDescription)"],
                warnings: []
            )
        }

        guard requireSyncPath else {
            return TeachingCommercialPreflightResult(blockingErrors: [], warnings: [])
        }

        for student in students {
            let profile: TeachingStudentProfileSettings?
            do {
                profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
            } catch {
                warnings.append("读取学生配置失败：\(student.name)")
                continue
            }

            let syncPath = (profile?.syncBaseFolderPath ?? defaults.syncBaseFolderPath)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if syncPath.isEmpty {
                blockingErrors.append("未配置同步目录：\(student.name)")
            }
        }

        return TeachingCommercialPreflightResult(
            blockingErrors: blockingErrors,
            warnings: warnings
        )
    }

    static func repair(students: [TeachingStudentItem]) throws -> [String] {
        var messages: [String] = []
        let workspace = try ArchiveStorage.ensureWorkspace()
        let systemFolder = workspace
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: systemFolder, withIntermediateDirectories: true)

        let baselineFolder = systemFolder.appendingPathComponent("course-sync-baselines", isDirectory: true)
        try FileManager.default.createDirectory(at: baselineFolder, withIntermediateDirectories: true)
        messages.append("已确保同步基线目录存在")

        let conflictFolder = systemFolder.appendingPathComponent("course-sync-conflicts", isDirectory: true)
        if FileManager.default.fileExists(atPath: conflictFolder.path) {
            let urls = try FileManager.default.contentsOfDirectory(
                at: conflictFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in urls where url.pathExtension.lowercased() == "log" {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.isEmpty { continue }
                var normalized: [String] = []
                for line in text.split(separator: "\n") {
                    guard let data = String(line).data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let sourceFile = json["sourceFile"] as? String,
                          let sourceID = json["sourceID"] as? String,
                          !sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }
                    normalized.append(String(line))
                }
                let output = normalized.joined(separator: "\n")
                let finalText = output.isEmpty ? "" : output + "\n"
                try finalText.write(to: url, atomically: true, encoding: .utf8)
            }
            messages.append("已清理冲突日志坏行")
        }

        let signatureLog = systemFolder.appendingPathComponent("course-export-signatures.log", isDirectory: false)
        if !FileManager.default.fileExists(atPath: signatureLog.path) {
            try "".write(to: signatureLog, atomically: true, encoding: .utf8)
            messages.append("已创建导出签名日志")
        }

        if students.isEmpty {
            messages.append("未传入学生列表，仅完成系统层修复")
        }
        return messages
    }

    static func run(students: [TeachingStudentItem]) throws -> TeachingCommercialReadinessReport {
        var totalChecks = 0
        var warningCount = 0
        var errorCount = 0
        var messages: [String] = []

        let workspace = try ArchiveStorage.ensureWorkspace()
        let systemFolder = workspace
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)

        // 1) 配置快照schema检查
        totalChecks += 1
        do {
            let snapshot = try TeachingStudentSettingsStore.loadSnapshot()
            if snapshot.schemaVersion < TeachingSettingsSnapshot.currentSchemaVersion {
                warningCount += 1
                messages.append("⚠️ 设置版本较旧：\(snapshot.schemaVersion) < \(TeachingSettingsSnapshot.currentSchemaVersion)")
            } else {
                messages.append("✅ 设置版本检查通过")
            }
        } catch {
            errorCount += 1
            messages.append("❌ 设置快照读取失败：\(error.localizedDescription)")
        }

        // 2) 三向合并基线检查
        totalChecks += 1
        let baselineFolder = systemFolder.appendingPathComponent("course-sync-baselines", isDirectory: true)
        if FileManager.default.fileExists(atPath: baselineFolder.path) {
            for student in students {
                let baselineFile = baselineFolder.appendingPathComponent("\(student.id.uuidString).json", isDirectory: false)
                guard FileManager.default.fileExists(atPath: baselineFile.path) else { continue }
                let data = try Data(contentsOf: baselineFile)
                guard let baselineMap = try? JSONDecoder().decode([String: String].self, from: data) else {
                    errorCount += 1
                    messages.append("❌ 基线文件损坏：\(student.name)")
                    continue
                }
                for (key, digest) in baselineMap {
                    if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        warningCount += 1
                        messages.append("⚠️ 基线存在空Key：\(student.name)")
                        continue
                    }
                    if digest.count != 64 {
                        warningCount += 1
                        messages.append("⚠️ 基线摘要长度异常：\(student.name) - \(key)")
                    }
                }
            }
            messages.append("✅ 同步基线检查完成")
        } else {
            warningCount += 1
            messages.append("⚠️ 未发现同步基线目录（首次运行可忽略）")
        }

        // 3) 冲突日志结构检查
        totalChecks += 1
        let conflictFolder = systemFolder.appendingPathComponent("course-sync-conflicts", isDirectory: true)
        if FileManager.default.fileExists(atPath: conflictFolder.path) {
            let urls = try FileManager.default.contentsOfDirectory(
                at: conflictFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in urls where url.pathExtension.lowercased() == "log" {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.isEmpty { continue }
                for line in text.split(separator: "\n") {
                    guard let data = String(line).data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        warningCount += 1
                        messages.append("⚠️ 冲突日志存在不可解析行：\(url.lastPathComponent)")
                        continue
                    }
                    let sourceFile = (json["sourceFile"] as? String) ?? ""
                    let sourceID = (json["sourceID"] as? String) ?? ""
                    if sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        warningCount += 1
                        messages.append("⚠️ 冲突日志缺字段：\(url.lastPathComponent)")
                    }
                }
            }
            messages.append("✅ 冲突日志检查完成")
        } else {
            messages.append("✅ 冲突日志目录不存在（无冲突记录）")
        }

        // 4) 导出签名校验
        totalChecks += 1
        let signatureLog = systemFolder.appendingPathComponent("course-export-signatures.log", isDirectory: false)
        if FileManager.default.fileExists(atPath: signatureLog.path) {
            let content = try String(contentsOf: signatureLog, encoding: .utf8)
            let lines = content.split(separator: "\n").suffix(300)
            for line in lines {
                guard let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    warningCount += 1
                    messages.append("⚠️ 导出签名日志有损坏行")
                    continue
                }

                let destinationPath = (json["destinationPath"] as? String) ?? ""
                let expectedDigest = (json["sha256"] as? String) ?? ""
                if destinationPath.isEmpty || expectedDigest.isEmpty {
                    warningCount += 1
                    messages.append("⚠️ 导出签名日志缺字段")
                    continue
                }

                let targetURL = URL(fileURLWithPath: destinationPath)
                guard FileManager.default.fileExists(atPath: targetURL.path) else {
                    warningCount += 1
                    messages.append("⚠️ 已签名导出文件不存在：\(targetURL.lastPathComponent)")
                    continue
                }

                let fileData = try Data(contentsOf: targetURL)
                let digest = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
                if digest != expectedDigest {
                    errorCount += 1
                    messages.append("❌ 导出签名校验失败：\(targetURL.lastPathComponent)")
                }
            }
            messages.append("✅ 导出签名检查完成")
        } else {
            warningCount += 1
            messages.append("⚠️ 暂无导出签名日志")
        }

        return TeachingCommercialReadinessReport(
            totalChecks: totalChecks,
            warningCount: warningCount,
            errorCount: errorCount,
            messages: messages
        )
    }
}
