import SwiftUI
import SwiftData

@main
struct BruhApp: App {
    @State private var hasSeeded = false
    @State private var modelContainer: ModelContainer

    init() {
        _modelContainer = State(initialValue: Self.makeModelContainer())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    if !hasSeeded {
                        seedPersonas(into: modelContainer.mainContext)
                        seedSystemContacts(into: modelContainer.mainContext)
                        hasSeeded = true
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Persona.self,
            PersonaPost.self,
            SourceItem.self,
            MessageThread.self,
            PersonaMessage.self,
            FeedComment.self,
            FeedLike.self,
            Contact.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            clearDefaultStoreFiles()

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // Last-resort fallback to keep app bootable.
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    fatalError("Failed to create SwiftData ModelContainer: \(error)")
                }
            }
        }
    }

    private static func clearDefaultStoreFiles() {
        let fileManager = FileManager.default
        let appSupport = URL.applicationSupportDirectory
        let storeURL = appSupport.appendingPathComponent("default.store")
        let fileURLs = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
        ]

        for url in fileURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
