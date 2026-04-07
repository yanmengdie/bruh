import SwiftUI
import SwiftData

@main
struct BruhApp: App {
    @State private var hasSeeded = false
    @State private var modelContainer: ModelContainer

    init() {
        _modelContainer = State(initialValue: try! ModelContainer(
            for: Persona.self,
            PersonaPost.self,
            SourceItem.self,
            MessageThread.self,
            PersonaMessage.self,
            FeedComment.self,
            FeedLike.self
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    if !hasSeeded {
                        seedPersonas(into: modelContainer.mainContext)
                        hasSeeded = true
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
