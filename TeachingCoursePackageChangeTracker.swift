import Foundation

@MainActor
final class TeachingCoursePackageChangeTracker {
    struct PackageDisplayItem: Identifiable {
        var id: String
        var title: String
        var sourceFile: String
    }
    struct RowSnapshot {
        var rowIndex: Int
        var nodeID: UUID
        var level: Int
        var text: String
        var owningH3ID: String?
        var isH3: Bool
        var sourceFile: String
    }

    private(set) var pendingUpdateCount: Int = 0
    private(set) var isRefreshing: Bool = false

    private var pendingRefreshTask: Task<Void, Never>?
    private var lastRefreshAt: Date = .distantPast
    private var activeRowSnapshot: RowSnapshot?
    private var dirtyPackageIDs: Set<String> = []
    private var newPackageOrderedIDs: [String] = []
    private var newPackageIDSet: Set<String> = []
    private var baselineDigestByH3ID: [String: String] = [:]

    func establishBaseline(document: NodeMarkdownDocument) {
        dirtyPackageIDs.removeAll()
        newPackageOrderedIDs.removeAll()
        newPackageIDSet.removeAll()
        activeRowSnapshot = nil
        baselineDigestByH3ID = TeachingCoursePackageContentSignature.digestByH3ID(in: document)
        reconcileNewPackageList(with: document)
    }

    /// External notebook writes may insert linked lesson packages, but must not redefine the
    /// session baseline for packages the teacher has already edited. Merge the new disk truth
    /// into the existing tracker instead of clearing dirty/new queues.
    func reconcileAfterExternalReload(
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument
    ) -> Int {
        recordDocumentMutation(
            previousDocument: previousDocument,
            currentDocument: currentDocument
        )
    }

    func schedulePendingRefresh(
        student: TeachingStudentItem?,
        onCountUpdated: @escaping @MainActor (Int) -> Void,
        minimumInterval: TimeInterval = 0,
        force: Bool = false
    ) {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            if !force, minimumInterval > 0 {
                let elapsed = Date().timeIntervalSince(self.lastRefreshAt)
                let delay = max(0, minimumInterval - elapsed)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            guard !Task.isCancelled else { return }
            await self.refreshNow(student: student, onCountUpdated: onCountUpdated)
        }
    }

    func refreshNow(
        student: TeachingStudentItem?,
        onCountUpdated: @escaping @MainActor (Int) -> Void
    ) async {
        guard !isRefreshing else { return }
        guard let student else {
            pendingUpdateCount = 0
            lastRefreshAt = Date()
            onCountUpdated(0)
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        do {
            let preview = try await TeachingCoursePackageSyncExecutor.previewUpdate(student: student)
            pendingUpdateCount = preview.totalPendingCount
            onCountUpdated(pendingUpdateCount)
        } catch {
            pendingUpdateCount = 0
            onCountUpdated(0)
        }
    }

    func loadPreview(student: TeachingStudentItem) async throws -> TeachingCourseUpdatePreview {
        let preview = try await TeachingCoursePackageSyncExecutor.previewUpdate(student: student)
        pendingUpdateCount = preview.totalPendingCount
        lastRefreshAt = Date()
        return preview
    }

    func resetPendingCount() -> Int {
        pendingUpdateCount = 0
        lastRefreshAt = Date()
        return pendingUpdateCount
    }

    func localPendingCount() -> Int {
        dirtyPackageIDs.count + newPackageOrderedIDs.count
    }

    func dirtyPackageIDList() -> [String] {
        Array(dirtyPackageIDs)
    }

    func newPackageIDList() -> [String] {
        newPackageOrderedIDs
    }

    func dirtyPackageDisplayItems(document: NodeMarkdownDocument) -> [PackageDisplayItem] {
        let set = dirtyPackageIDs
        return document.nodes
            .filter { $0.level == 3 && set.contains($0.id.uuidString) }
            .map {
                PackageDisplayItem(
                    id: $0.id.uuidString,
                    title: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceFile: $0.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }

    func newPackageDisplayItems(document: NodeMarkdownDocument) -> [PackageDisplayItem] {
        reconcileNewPackageList(with: document)
        var byID: [String: NodeMarkdownNode] = [:]
        for node in document.nodes where node.level == 3 {
            byID[node.id.uuidString] = node
        }
        let ids = newPackageOrderedIDs
        var staleIDs: [String] = []
        var items: [PackageDisplayItem] = []
        items.reserveCapacity(ids.count)
        for id in ids {
            guard let node = byID[id] else {
                staleIDs.append(id)
                continue
            }
            guard isNewPackageRoot(node) else {
                staleIDs.append(id)
                continue
            }
            items.append(PackageDisplayItem(
                id: id,
                title: node.text.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceFile: node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        staleIDs.forEach { removeNewPackage(h3NodeID: $0) }
        return items
    }

    func resetLocalQueues() {
        dirtyPackageIDs.removeAll()
        newPackageOrderedIDs.removeAll()
        newPackageIDSet.removeAll()
        activeRowSnapshot = nil
    }

    func beginTrackingRow(
        rowIndex: Int?,
        document: NodeMarkdownDocument,
        structuralIndex: NodeMarkdownDocumentIndex? = nil
    ) {
        guard let rowIndex, document.nodes.indices.contains(rowIndex) else {
            activeRowSnapshot = nil
            return
        }
        activeRowSnapshot = snapshotForRow(
            rowIndex,
            document: document,
            structuralIndex: structuralIndex
        )
    }

    func finishTrackingPreviousRow(
        newRowIndex: Int?,
        document: NodeMarkdownDocument,
        structuralIndex: NodeMarkdownDocumentIndex? = nil
    ) -> Int {
        defer {
            reconcileNewPackageList(with: document)
            if let newRowIndex, document.nodes.indices.contains(newRowIndex) {
                activeRowSnapshot = snapshotForRow(
                    newRowIndex,
                    document: document,
                    structuralIndex: structuralIndex
                )
            } else {
                activeRowSnapshot = nil
            }
        }
        guard let snapshot = activeRowSnapshot else { return localPendingCount() }
        let indexedRow = structuralIndex?.row(for: snapshot.nodeID)
        guard let currentRowIndex = indexedRow ?? document.nodes.firstIndex(where: { $0.id == snapshot.nodeID }) else {
            if let owningH3ID = snapshot.owningH3ID {
                classifyExistingH3Package(h3NodeID: owningH3ID, document: document)
            }
            return localPendingCount()
        }

        let current = snapshotForRow(
            currentRowIndex,
            document: document,
            structuralIndex: structuralIndex
        )
        if snapshot.level != current.level || snapshot.text != current.text {
            if let owningH3ID = current.owningH3ID ?? snapshot.owningH3ID {
                classifyExistingH3Package(h3NodeID: owningH3ID, document: document)
            }
        }

        if current.isH3 {
            if document.nodes.indices.contains(current.rowIndex),
               isNewPackageRoot(document.nodes[current.rowIndex]) {
                addNewPackage(currentNodeIDAtRow: current.rowIndex, document: document)
            }
        }
        return localPendingCount()
    }

    func recordParseMutation(
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument,
        activeRowIndex: Int?
    ) -> Int {
        _ = activeRowIndex
        return recordDocumentMutation(
            previousDocument: previousDocument,
            currentDocument: currentDocument
        )
    }

    func recordDocumentMutation(
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument
    ) -> Int {
        var previousH3ByID: [String: NodeMarkdownNode] = [:]
        for node in previousDocument.nodes where node.level == 3 {
            previousH3ByID[node.id.uuidString] = node
        }
        let previousDigests = TeachingCoursePackageContentSignature.digestByH3ID(in: previousDocument)
        let currentDigests = TeachingCoursePackageContentSignature.digestByH3ID(in: currentDocument)
        let currentH3Nodes = currentDocument.nodes.filter { $0.level == 3 }
        let currentH3IDs = Set(currentH3Nodes.map { $0.id.uuidString })

        // Demoted or deleted H3 roots no longer own a package. They must disappear from both
        // queues immediately, especially source-less H3 roots that used to be new packages.
        let trackedIDs = dirtyPackageIDs.union(newPackageIDSet)
        for staleID in trackedIDs where !currentH3IDs.contains(staleID) {
            dirtyPackageIDs.remove(staleID)
            removeNewPackage(h3NodeID: staleID)
            baselineDigestByH3ID.removeValue(forKey: staleID)
        }

        for node in currentH3Nodes {
            let id = node.id.uuidString
            if isNewPackageRoot(node) {
                dirtyPackageIDs.remove(id)
                addNewPackage(nodeID: id)
                continue
            }

            removeNewPackage(h3NodeID: id)
            guard hasCompleteSourceLink(node), let currentDigest = currentDigests[id] else {
                dirtyPackageIDs.remove(id)
                continue
            }

            if baselineDigestByH3ID[id] == nil {
                if let previousNode = previousH3ByID[id],
                   hasCompleteSourceLink(previousNode),
                   let previousDigest = previousDigests[id] {
                    baselineDigestByH3ID[id] = previousDigest
                } else {
                    // A linked package inserted from a lesson plan enters the session clean.
                    baselineDigestByH3ID[id] = currentDigest
                }
            }

            if baselineDigestByH3ID[id] == currentDigest {
                dirtyPackageIDs.remove(id)
            } else {
                dirtyPackageIDs.insert(id)
            }
        }

        baselineDigestByH3ID = baselineDigestByH3ID.filter { currentH3IDs.contains($0.key) }
        reconcileNewPackageList(with: currentDocument)
        return localPendingCount()
    }

    func recordTouchedH3Packages(
        h3NodeIDs: Set<String>,
        document: NodeMarkdownDocument
    ) -> Int {
        guard !h3NodeIDs.isEmpty else { return localPendingCount() }
        let idSet = Set(h3NodeIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        for node in document.nodes where node.level == 3 && idSet.contains(node.id.uuidString) {
            classifyH3Package(node, document: document)
        }
        reconcileNewPackageList(with: document)
        return localPendingCount()
    }

    func recordNewPackageDeletion(h3NodeID: String) -> Int {
        removeNewPackage(h3NodeID: h3NodeID)
        dirtyPackageIDs.remove(h3NodeID)
        return localPendingCount()
    }

    func recordRemovedNodePackage(
        removedNodes: [NodeMarkdownNode],
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument
    ) -> Int {
        for node in removedNodes where node.level == 3 {
            classifyRemovedH3Package(node)
        }

        let affectedOwnerIDs = h3OwnerIDsForRemovedChildNodes(
            removedNodes: removedNodes,
            previousDocument: previousDocument
        )
        for h3ID in affectedOwnerIDs {
            if let h3Node = currentDocument.nodes.first(where: { $0.id.uuidString == h3ID && $0.level == 3 }) {
                classifyH3Package(h3Node, document: currentDocument)
            }
        }

        reconcileNewPackageList(with: currentDocument)
        return localPendingCount()
    }

    func removeDirtyPackages(sourceIDs: Set<String>) {
        guard !sourceIDs.isEmpty else { return }
        for sourceID in sourceIDs {
            let trimmed = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            dirtyPackageIDs.remove(trimmed)
        }
    }

    func removeDirtyPackages(sourceIDs: Set<String>, document: NodeMarkdownDocument) {
        guard !sourceIDs.isEmpty else { return }
        var idsToRemove = sourceIDs
        for node in document.nodes where node.level == 3 {
            let sourceID = node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceIDs.contains(sourceID) {
                idsToRemove.insert(node.id.uuidString)
                if let digest = packageDigest(h3NodeID: node.id.uuidString, document: document) {
                    baselineDigestByH3ID[node.id.uuidString] = digest
                }
            }
        }
        removeDirtyPackages(sourceIDs: idsToRemove)
    }

    func acceptSuccessfulSyncResults(
        _ results: [TeachingCourseSyncPackageResult],
        document: NodeMarkdownDocument
    ) {
        for result in results where result.success {
            guard result.reason != "new package skipped by selection",
                  result.reason != "mother-source update pending; active notebook preserved" else { continue }
            let sourceID = result.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceID.isEmpty else { continue }
            guard let node = document.nodes.first(where: {
                $0.level == 3
                    && ($0.id.uuidString.caseInsensitiveCompare(sourceID) == .orderedSame
                        || $0.sourceID.caseInsensitiveCompare(sourceID) == .orderedSame)
            }) else { continue }
            let nodeID = node.id.uuidString
            if let digest = packageDigest(h3NodeID: nodeID, document: document) {
                baselineDigestByH3ID[nodeID] = digest
            }
            dirtyPackageIDs.remove(nodeID)
            removeNewPackage(h3NodeID: nodeID)
        }
    }

    private func snapshotForRow(
        _ rowIndex: Int,
        document: NodeMarkdownDocument,
        structuralIndex: NodeMarkdownDocumentIndex? = nil
    ) -> RowSnapshot {
        let node = document.nodes[rowIndex]
        let owningH3Index = document.owningH3Index(
            for: rowIndex,
            structuralIndex: structuralIndex
        )
        let owningH3ID = owningH3Index.flatMap { index in
            document.nodes.indices.contains(index) ? document.nodes[index].id.uuidString : nil
        }
        return RowSnapshot(
            rowIndex: rowIndex,
            nodeID: node.id,
            level: node.level,
            text: node.text,
            owningH3ID: owningH3ID,
            isH3: node.level == 3,
            sourceFile: node.sourceFile
        )
    }

    private func classifyH3Package(_ node: NodeMarkdownNode, document: NodeMarkdownDocument) {
        guard node.level == 3 else { return }
        removeNewPackage(h3NodeID: node.id.uuidString)
        if isNewPackageRoot(node) {
            dirtyPackageIDs.remove(node.id.uuidString)
            addNewPackage(nodeID: node.id.uuidString)
        } else if hasCompleteSourceLink(node) {
            guard let currentDigest = packageDigest(h3NodeID: node.id.uuidString, document: document) else {
                dirtyPackageIDs.remove(node.id.uuidString)
                return
            }
            guard let baselineDigest = baselineDigestByH3ID[node.id.uuidString] else {
                baselineDigestByH3ID[node.id.uuidString] = currentDigest
                dirtyPackageIDs.remove(node.id.uuidString)
                return
            }
            if currentDigest == baselineDigest {
                dirtyPackageIDs.remove(node.id.uuidString)
            } else {
                dirtyPackageIDs.insert(node.id.uuidString)
            }
        } else {
            dirtyPackageIDs.remove(node.id.uuidString)
        }
    }

    private func classifyExistingH3Package(h3NodeID: String, document: NodeMarkdownDocument) {
        guard let node = document.nodes.first(where: {
            $0.level == 3 && $0.id.uuidString == h3NodeID
        }) else {
            removeNewPackage(h3NodeID: h3NodeID)
            dirtyPackageIDs.remove(h3NodeID)
            baselineDigestByH3ID.removeValue(forKey: h3NodeID)
            return
        }
        classifyH3Package(node, document: document)
    }

    private func packageDigest(h3NodeID: String, document: NodeMarkdownDocument) -> String? {
        guard let rootID = UUID(uuidString: h3NodeID),
              let range = TeachingCoursePackageContentSignature.packageRange(
                  in: document.nodes,
                  rootID: rootID
              ) else {
            return nil
        }
        return TeachingCoursePackageContentSignature.digest(
            Array(document.nodes[range.start..<range.end])
        )
    }

    private func isNewPackageRoot(_ node: NodeMarkdownNode) -> Bool {
        TeachingCoursePackageContentSignature.isCollectableNewPackageRoot(node)
    }

    private func hasCompleteSourceLink(_ node: NodeMarkdownNode) -> Bool {
        let sourceID = node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceFile = node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sourceID.isEmpty && !sourceFile.isEmpty
    }

    private func classifyRemovedH3Package(_ node: NodeMarkdownNode) {
        removeNewPackage(h3NodeID: node.id.uuidString)
        dirtyPackageIDs.remove(node.id.uuidString)
    }

    private func h3OwnerIDsForRemovedChildNodes(
        removedNodes: [NodeMarkdownNode],
        previousDocument: NodeMarkdownDocument
    ) -> Set<String> {
        let previousIndex = NodeMarkdownDocumentIndex(nodes: previousDocument.nodes)
        let removedNodeIDs = Set(removedNodes.map(\.id))
        var ownerIDs: Set<String> = []
        for node in removedNodes where node.level != 3 {
            guard let previousRow = previousIndex.row(for: node.id),
                  let ownerIndex = previousIndex.owningH3Row(for: previousRow),
                  previousDocument.nodes.indices.contains(ownerIndex) else {
                continue
            }
            let owner = previousDocument.nodes[ownerIndex]
            guard !removedNodeIDs.contains(owner.id) else { continue }
            ownerIDs.insert(owner.id.uuidString)
        }
        return ownerIDs
    }

    private func addNewPackage(currentNodeIDAtRow rowIndex: Int, document: NodeMarkdownDocument) {
        guard document.nodes.indices.contains(rowIndex) else { return }
        let node = document.nodes[rowIndex]
        guard isNewPackageRoot(node) else { return }
        addNewPackage(nodeID: node.id.uuidString)
    }

    private func addNewPackage(nodeID: String) {
        let id = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard !newPackageIDSet.contains(id) else { return }
        newPackageIDSet.insert(id)
        newPackageOrderedIDs.append(id)
    }

    // 名单长期保留并随编辑事件增删；完整扫描只负责校准，不承担日常发现的唯一职责。
    private func reconcileNewPackageList(with document: NodeMarkdownDocument) {
        let currentIDs = document.nodes.compactMap { node -> String? in
            isNewPackageRoot(node) ? node.id.uuidString : nil
        }
        let currentIDSet = Set(currentIDs)

        if newPackageIDSet != newPackageIDSet.intersection(currentIDSet) {
            newPackageIDSet.formIntersection(currentIDSet)
            newPackageOrderedIDs.removeAll { !currentIDSet.contains($0) }
        }
        for id in currentIDs where !newPackageIDSet.contains(id) {
            newPackageIDSet.insert(id)
            newPackageOrderedIDs.append(id)
        }
    }

    private func removeNewPackage(h3NodeID: String) {
        guard newPackageIDSet.contains(h3NodeID) else { return }
        newPackageIDSet.remove(h3NodeID)
        newPackageOrderedIDs.removeAll(where: { $0 == h3NodeID })
    }
}
