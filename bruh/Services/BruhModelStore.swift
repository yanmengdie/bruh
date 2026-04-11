import Foundation
import SwiftData

enum BruhSchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Persona.self,
            PersonaPost.self,
            PengyouMoment.self,
            SourceItem.self,
            ContentEvent.self,
            ContentDelivery.self,
            MessageThread.self,
            PersonaMessage.self,
            FeedComment.self,
            FeedLike.self,
            FeedInteractionSeedState.self,
            Contact.self,
            UserProfile.self,
        ]
    }
}

enum BruhSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BruhSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum BruhModelStore {
    static let schema = Schema(BruhSchemaV1.models)

    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try makePersistentContainer(configuration: configuration)
        } catch {
            backupDefaultStoreFiles(reason: "container_boot_failure")
            clearDefaultStoreFiles()

            do {
                return try makePersistentContainer(configuration: configuration)
            } catch {
                // Last-resort fallback to keep app bootable.
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, migrationPlan: BruhSchemaMigrationPlan.self, configurations: [memoryConfig])
                } catch {
                    fatalError("Failed to create SwiftData ModelContainer: \(error)")
                }
            }
        }
    }

    private static func makePersistentContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: BruhSchemaMigrationPlan.self, configurations: [configuration])
    }

    private static func clearDefaultStoreFiles(fileManager: FileManager = .default) {
        for url in defaultStoreFileURLs() where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func backupDefaultStoreFiles(reason: String, fileManager: FileManager = .default) {
        let existingStoreURLs = defaultStoreFileURLs().filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingStoreURLs.isEmpty else { return }

        let timestamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = URL.applicationSupportDirectory
            .appendingPathComponent("store-backups", isDirectory: true)
            .appendingPathComponent("\(timestamp)-\(reason)", isDirectory: true)

        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        for sourceURL in existingStoreURLs {
            let destinationURL = backupDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func defaultStoreFileURLs() -> [URL] {
        let storeURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        return [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
        ]
    }
}
