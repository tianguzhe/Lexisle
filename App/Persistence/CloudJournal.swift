import CloudKit
import CoreData
import Foundation
import SwiftData

enum PersistenceError: LocalizedError {
    case invalidCloudContainer

    var errorDescription: String? {
        "尚未配置 iCloud Container，请先在 Xcode 中设置签名和 iCloud。"
    }
}

/// Owns CloudKit's mirrored store. Local session state never enters this store.
@MainActor
final class CloudJournal {
    enum Event {
        case remoteChange
        case transferStarted
        case transferCompleted(Date)
        case transferFailed(String)
    }

    private let container: ModelContainer
    private let context: ModelContext
    private let identifier: String
    private var observations: [NotificationObservation] = []

    init(directory: URL, identifier: String?) throws {
        guard let identifier, identifier.hasPrefix("iCloud."), !identifier.contains("$(") else {
            throw PersistenceError.invalidCloudContainer
        }
        self.identifier = identifier
        let schema = Schema(versionedSchema: CloudSchemaV1.self)
        let configuration = ModelConfiguration(
            "Cloud", schema: schema, url: directory.appendingPathComponent("cloud.store"),
            cloudKitDatabase: .private(identifier)
        )
        container = try ModelContainer(
            for: schema, migrationPlan: CloudMigrationPlan.self, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await CKContainer(identifier: identifier).accountStatus()
    }

    func operations() throws -> [LearningOperation] {
        let records = try context.fetch(FetchDescriptor<CloudJournalEntry>())
        let decoder = JSONDecoder()
        return try records.map { try decoder.decode(LearningOperation.self, from: $0.payload) }
    }

    func enqueue(_ operations: [LearningOperation]) throws {
        var existing = Set(try context.fetch(FetchDescriptor<CloudJournalEntry>()).map(\.operationID))
        let encoder = JSONEncoder()
        do {
            for operation in operations where existing.insert(operation.id).inserted {
                context.insert(
                    CloudJournalEntry(
                        operationID: operation.id, createdAt: operation.date, payload: try encoder.encode(operation)
                    ))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func observe(_ handler: @escaping @MainActor (Event) -> Void) {
        observations.removeAll()
        let center = NotificationCenter.default
        let remote = center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            Task { @MainActor in handler(.remoteChange) }
        }
        let progress = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }
            let ended = event.endDate
            let succeeded = event.succeeded
            let isTransfer = event.type == .export || event.type == .import
            let message = event.error?.localizedDescription
            Task { @MainActor in
                if let ended, isTransfer, succeeded {
                    handler(.transferCompleted(ended))
                } else if ended == nil {
                    handler(.transferStarted)
                } else if let message {
                    handler(.transferFailed(message))
                }
            }
        }
        observations = [NotificationObservation(token: remote), NotificationObservation(token: progress)]
    }
}
