import Foundation

@MainActor
struct StarterMessageLifecycle {
    let api: APIClient
    let runtimeOptions: AppRuntimeOptions
    let threadStore: MessageThreadStore

    init(
        api: APIClient,
        runtimeOptions: AppRuntimeOptions,
        threadStore: MessageThreadStore
    ) {
        self.api = api
        self.runtimeOptions = runtimeOptions
        self.threadStore = threadStore
    }
}
