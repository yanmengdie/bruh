import SwiftUI
import SwiftData

@main
struct BruhApp: App {
    @State private var modelContainer: ModelContainer

    init() {
        _modelContainer = State(initialValue: BruhModelStore.makeContainer())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
