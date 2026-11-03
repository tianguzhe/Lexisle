import Foundation
import SwiftData

// Keep model names, stored attributes and V1 schema identifiers stable across refactors.
@Model final class LocalSnapshot {
    var key: String = "session"
    var payload: Data = Data()
    init(key: String = "session", payload: Data = Data()) {
        self.key = key
        self.payload = payload
    }
}

@Model final class LocalJournalEntry {
    var operationID: String = ""
    var createdAt: Date = Date.distantPast
    var payload: Data = Data()
    var cloudSubmitted: Bool = false
    init(operation: LearningOperation, payload: Data, cloudSubmitted: Bool = false) {
        self.operationID = operation.id
        self.createdAt = operation.date
        self.payload = payload
        self.cloudSubmitted = cloudSubmitted
    }
}

/// CloudKit models have defaults and no uniqueness constraints. Deduplication is by operationID.
@Model final class CloudJournalEntry {
    var operationID: String = ""
    var createdAt: Date = Date.distantPast
    var payload: Data = Data()
    init(operationID: String, createdAt: Date, payload: Data) {
        self.operationID = operationID
        self.createdAt = createdAt
        self.payload = payload
    }
}

enum LocalSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [LocalSnapshot.self, LocalJournalEntry.self] }
}

enum CloudSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [CloudJournalEntry.self] }
}

enum LocalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LocalSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum CloudMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CloudSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
