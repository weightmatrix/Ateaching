import SwiftUI

extension Notification.Name {
    static let teachingReflectionImageExported = Notification.Name("ATeaching.reflectionImageExported")
    static let teachingScheduleConnectionChanged = Notification.Name("ATeaching.scheduleConnectionChanged")
}

struct TeachingScheduleRoster: Decodable {
    struct Student: Decodable, Identifiable {
        let id: UUID
        let name: String
        let color: String
        let recycled: Bool
        let teachingProfile: TeachingScheduleProfile?

        enum CodingKeys: String, CodingKey {
            case id = "uuid"
            case name, color
            case recycled = "is_recycled"
            case teachingProfile = "teaching_profile"
        }
    }

    struct Course: Decodable {
        let id: UUID
        let start: String
        let end: String

        enum CodingKeys: String, CodingKey {
            case id = "uuid"
            case start = "start_time"
            case end = "end_time"
        }
    }

    struct Manager: Decodable, Identifiable {
        let id: UUID
        let name: String

        enum CodingKeys: String, CodingKey {
            case id = "uuid"
            case name
        }
    }

    let teacherID: UUID
    let managers: [Manager]
    let students: [Student]
    let latestCourses: [String: Course]

    enum CodingKeys: String, CodingKey {
        case teacherID = "teacher_id"
        case students, managers
        case latestCourses = "latest_courses"
    }
}

nonisolated struct TeachingScheduleProfile: Codable, Equatable {
    var iconName: String?
    var studentInfoTemplateID: String?
    var studentNameKeyID: String?
    var classInfoTemplateID: String?
    var classInfoNameKeyID: String?
    var classInfoContentKeyID: String?
    var classInfoTimeKeyID: String?
    var lessonPlanFolderIDs: [String]?
    var workbookFileID: String?

    init(iconName: String, settings: TeachingStudentProfileSettings) {
        self.iconName = iconName
        studentInfoTemplateID = settings.studentInfoTemplateID
        studentNameKeyID = settings.studentNameKeyID
        classInfoTemplateID = settings.classInfoTemplateID
        classInfoNameKeyID = settings.classInfoNameKeyID
        classInfoContentKeyID = settings.classInfoContentKeyID
        classInfoTimeKeyID = settings.classInfoTimeKeyID
        lessonPlanFolderIDs = settings.lessonPlanFolderIDs
        workbookFileID = settings.workbookFileID
    }

    func apply(to settings: inout TeachingStudentProfileSettings) {
        settings.studentInfoTemplateID = studentInfoTemplateID
        settings.studentNameKeyID = studentNameKeyID
        settings.classInfoTemplateID = classInfoTemplateID
        settings.classInfoNameKeyID = classInfoNameKeyID
        settings.classInfoContentKeyID = classInfoContentKeyID
        settings.classInfoTimeKeyID = classInfoTimeKeyID
        settings.lessonPlanFolderIDs = lessonPlanFolderIDs ?? []
        settings.workbookFileID = workbookFileID
    }
}

extension TeachingScheduleConnection {
    func roster() async throws -> TeachingScheduleRoster {
        let data = try await Self.send(to: resource.appendingPathComponent("roster", isDirectory: true),
                                       method: "GET", secret: secret)
        return try JSONDecoder().decode(TeachingScheduleRoster.self, from: data)
    }

    func writeStudent(id: UUID, method: String, fields: [String: String]? = nil, profile: TeachingScheduleProfile? = nil) async throws {
        let url = resource.appendingPathComponent("students", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        var payload: [String: Any] = fields ?? [:]
        if let profile {
            payload["teaching_profile"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
        }
        let body = method == "DELETE" ? nil : try JSONSerialization.data(withJSONObject: payload)
        _ = try await Self.send(to: url, method: method, secret: secret, body: body)
    }

    func publishCatalog() async throws {
        let selection = try TeachingStudentSelectionSupport.loadSelectionData()
        let catalog: [String: Any] = [
            "icons": TeachingStudentItem.supportedIcons.map {
                ["id": $0, "title": TeachingStudentItem.displayName(forIcon: $0)]
            },
            "templates": selection.singleListTemplates.map { template in
                ["id": template.id, "title": template.title,
                 "rows": template.rows.map { ["id": $0.id, "title": $0.title] }] as [String: Any]
            },
            "workbooks": selection.checklistTemplates.map { ["id": $0.id, "title": $0.title] },
            "lessonPlans": selection.lessonPlanFolders
        ]
        let body = try JSONSerialization.data(withJSONObject: ["catalog": catalog])
        _ = try await Self.send(to: resource, method: "PATCH", secret: secret, body: body)
    }
}

@MainActor
enum TeachingScheduleStudentSync {
    static func adopt(_ remote: TeachingScheduleRoster.Student, teacherID: UUID, localID: UUID?) async throws {
        guard !remote.recycled else { return }
        let cleanName = remote.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName != ".", cleanName != "..",
              cleanName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:").union(.newlines)) == nil else {
            throw failure("排课学生姓名无法用作档案名称：\(remote.name)")
        }
        var snapshot = try TeachingStudentSettingsStore.loadSnapshot()
        guard !snapshot.hasCloudConflict else {
            throw failure("学生设置存在 iCloud 冲突，请先恢复学生设置。")
        }
        let matched = snapshot.students.first {
            $0.scheduleTeacherID == teacherID && $0.scheduleStudentID == remote.id
        }
        if let localID, let matched, matched.id != localID {
            throw failure("该排课学生已关联其他档案。")
        }
        let targetID = matched?.id ?? localID
        if let targetID {
            guard let target = snapshot.students.first(where: { $0.id == targetID }),
                  target.scheduleTeacherID == nil ||
                    (target.scheduleTeacherID == teacherID && target.scheduleStudentID == remote.id) else {
                throw failure("这个授课学生已关联其他排课档案。")
            }
            try await TeachingStudentRenameService.renameStudent(
                studentID: target.id, from: target.name, to: cleanName,
                scheduleIdentity: .init(studentID: remote.id, teacherID: teacherID, color: remote.color)
            )
            try applyRemoteProfile(remote, localID: remote.id)
            NotificationCenter.default.post(name: .teachingStudentsDidChange, object: nil)
            return
        } else {
            let archive = try ArchiveStorage.ensureArchiveRoot()
                .appendingPathComponent("学生", isDirectory: true)
                .appendingPathComponent(cleanName, isDirectory: true)
            guard !snapshot.students.contains(where: {
                $0.id == remote.id || $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }), !FileManager.default.fileExists(atPath: archive.path) else {
                throw failure("已存在名为「\(cleanName)」的授课档案，请先选择对应学生。")
            }
            var student = TeachingStudentItem(id: remote.id, name: cleanName, scheduleColorHex: remote.color,
                                              scheduleStudentID: remote.id, scheduleTeacherID: teacherID)
            if let teaching = remote.teachingProfile, teaching.iconName != nil {
                if let icon = teaching.iconName, TeachingStudentItem.supportedIcons.contains(icon) { student.iconName = icon }
                var profile = TeachingStudentProfileSettings()
                teaching.apply(to: &profile)
                TeachingStudentSelectionSupport.sanitizeSelections(&profile, using: try TeachingStudentSelectionSupport.loadSelectionData())
                snapshot.studentProfiles[student.id.uuidString] = profile
                student.scheduleProfile = teaching
            }
            snapshot.students.append(student)
        }
        try TeachingStudentSettingsStore.saveSnapshot(snapshot)
        NotificationCenter.default.post(name: .teachingStudentsDidChange, object: nil)
    }

    private static func applyRemoteProfile(_ remote: TeachingScheduleRoster.Student, localID: UUID) throws {
        guard let teaching = remote.teachingProfile, teaching.iconName != nil else { return }
        var snapshot = try TeachingStudentSettingsStore.loadSnapshot()
        guard let index = snapshot.students.firstIndex(where: { $0.id == localID }),
              snapshot.students[index].scheduleProfile != teaching else { return }
        if let icon = teaching.iconName, TeachingStudentItem.supportedIcons.contains(icon) {
            snapshot.students[index].iconName = icon
        }
        var profile = snapshot.studentProfiles[localID.uuidString] ?? TeachingStudentProfileSettings()
        teaching.apply(to: &profile)
        TeachingStudentSelectionSupport.sanitizeSelections(&profile, using: try TeachingStudentSelectionSupport.loadSelectionData())
        snapshot.studentProfiles[localID.uuidString] = profile
        snapshot.students[index].scheduleProfile = teaching
        try TeachingStudentSettingsStore.saveSnapshot(snapshot)
        NotificationCenter.default.post(name: .teachingStudentsDidChange, object: nil)
    }

    private static func initializationKey(_ teacherID: UUID) -> String {
        "teaching.schedule.initialized.\(teacherID.uuidString)"
    }

    static func completeInitialization(_ roster: TeachingScheduleRoster, students: [TeachingStudentItem]) {
        let remoteIDs = Set(students.filter { $0.scheduleTeacherID == roster.teacherID }.compactMap(\.scheduleStudentID))
        if !roster.students.contains(where: { !$0.recycled && !remoteIDs.contains($0.id) }) {
            UserDefaults.standard.set(true, forKey: initializationKey(roster.teacherID))
        }
    }

    static func pull(_ roster: TeachingScheduleRoster) async throws {
        guard TeachingClassSessionCenter.shared.session == nil,
              !(await TeachingCourseJobCenter.shared.hasActiveJobs()) else { return }
        var snapshot = try TeachingStudentSettingsStore.loadSnapshot()
        guard !snapshot.hasCloudConflict else { return }
        let backups = try TeachingStudentBackupService.listBackups()
        var changed = false
        for remote in roster.students {
            let live = snapshot.students.first {
                $0.scheduleTeacherID == roster.teacherID && $0.scheduleStudentID == remote.id
            }
            let backup = backups.first {
                $0.student.scheduleTeacherID == roster.teacherID && $0.student.scheduleStudentID == remote.id
            }
            if remote.recycled, let live {
                let archived = try TeachingStudentBackupService.backupStudents([live])
                guard archived.movedStudentIDs.contains(live.id) || backup != nil else {
                    throw failure("「\(live.name)」的档案未能移入备份。")
                }
                snapshot.students.removeAll { $0.id == live.id }
                snapshot.studentProfiles.removeValue(forKey: live.id.uuidString)
                changed = true
            } else if !remote.recycled, live == nil, let backup {
                guard !snapshot.students.contains(where: { $0.name == backup.student.name || $0.id == backup.student.id }) else {
                    throw failure("「\(backup.student.name)」恢复时与当前档案冲突。")
                }
                let restored = try TeachingStudentBackupService.restoreBackups([backup]) { student, profile in
                    var next = snapshot
                    next.students.append(student)
                    next.studentProfiles[student.id.uuidString] = profile
                    try TeachingStudentSettingsStore.saveSnapshot(next)
                }
                guard !restored.restoredStudents.isEmpty else {
                    throw failure("「\(backup.student.name)」的档案未能恢复。")
                }
                snapshot = try TeachingStudentSettingsStore.loadSnapshot()
                NotificationCenter.default.post(name: .teachingStudentsDidChange, object: nil)
            }
            if changed {
                try TeachingStudentSettingsStore.saveSnapshot(snapshot)
                snapshot = try TeachingStudentSettingsStore.loadSnapshot()
                NotificationCenter.default.post(name: .teachingStudentsDidChange, object: nil)
                changed = false
            }
        }
        for remote in roster.students where !remote.recycled {
            let local = snapshot.students.first {
                $0.scheduleTeacherID == roster.teacherID && $0.scheduleStudentID == remote.id
            }
            if let local {
                if local.name != remote.name || local.scheduleColorHex != remote.color {
                    try await adopt(remote, teacherID: roster.teacherID, localID: local.id)
                } else {
                    try applyRemoteProfile(remote, localID: local.id)
                }
            } else if UserDefaults.standard.bool(forKey: initializationKey(roster.teacherID)) {
                try await adopt(remote, teacherID: roster.teacherID, localID: nil)
            }
        }
    }

    static func saveProfile(_ profile: TeachingStudentProfileSettings, for student: TeachingStudentItem, icon: String? = nil) async throws {
        let selectedIcon = icon ?? student.iconName
        let teaching = TeachingScheduleProfile(iconName: selectedIcon, settings: profile)
        if let id = student.scheduleStudentID, let teacher = student.scheduleTeacherID,
           let connection = TeachingScheduleConnection.load() {
            guard try await connection.roster().teacherID == teacher else {
                throw failure("当前排课老师和这位学生的关联不一致。")
            }
            try await connection.writeStudent(id: id, method: "PATCH", profile: teaching)
        }
        var snapshot = try TeachingStudentSettingsStore.loadSnapshot()
        guard let index = snapshot.students.firstIndex(where: { $0.id == student.id }) else {
            throw failure("学生档案已经变更。")
        }
        snapshot.studentProfiles[student.id.uuidString] = profile
        snapshot.students[index].iconName = selectedIcon
        if student.scheduleStudentID != nil { snapshot.students[index].scheduleProfile = teaching }
        try TeachingStudentSettingsStore.saveSnapshot(snapshot)
        NotificationCenter.default.post(name: .teachingStudentsDidChange, object: nil)
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "ATeaching.Schedule.Roster", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct TeachingScheduleInitializationView: View {
    @State private var roster: TeachingScheduleRoster?
    @State private var localStudents: [TeachingStudentItem] = []
    @State private var choices: [UUID: UUID] = [:]
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        AppSettingsPage(title: "排课网初始化", subtitle: "关联排课网所有未进入回收站的学生") {
            AppSettingsCard(title: "学生名单", systemImage: "person.2") {
                Button("刷新排课名单") { run { try await reload() } }.disabled(busy)
                if let roster {
                    ForEach(roster.students.filter { !$0.recycled }) { remote in
                        HStack {
                            Text(remote.name)
                            Spacer()
                            if let matched = localStudents.first(where: {
                                $0.scheduleTeacherID == roster.teacherID && $0.scheduleStudentID == remote.id
                            }) {
                                Text(matched.name).foregroundStyle(.secondary)
                            } else {
                                Picker("对应授课学生", selection: Binding(
                                    get: { choices[remote.id] },
                                    set: { choices[remote.id] = $0 }
                                )) {
                                    Text("新建档案").tag(UUID?.none)
                                    ForEach(localStudents.filter { $0.scheduleTeacherID == nil }) { student in
                                        Text(student.name).tag(Optional(student.id))
                                    }
                                }
                                Button("关联") {
                                    run {
                                        try await TeachingScheduleStudentSync.adopt(
                                            remote, teacherID: roster.teacherID, localID: choices[remote.id]
                                        )
                                        localStudents = try TeachingStudentSettingsStore.loadSnapshot().students
                                        TeachingScheduleStudentSync.completeInitialization(roster, students: localStudents)
                                    }
                                }
                                .disabled(busy)
                            }
                        }
                    }
                }
                AppSettingsStatusMessage(message: message)
            }
        }
        .task { run { try await reload() } }
    }

    private func reload() async throws {
        guard let connection = TeachingScheduleConnection.load() else {
            throw TeachingScheduleStudentSync.failure("请先在项目设置打开联动并完成教师授权。")
        }
        let roster = try await connection.roster()
        self.roster = roster
        try await connection.publishCatalog()
        localStudents = try TeachingStudentSettingsStore.loadSnapshot().students
        TeachingScheduleStudentSync.completeInitialization(roster, students: localStudents)
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = ""
        Task {
            defer { busy = false }
            do { try await action() }
            catch { message = error.localizedDescription }
        }
    }
}
