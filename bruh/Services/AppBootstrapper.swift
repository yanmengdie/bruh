import Foundation
import SwiftData

@MainActor
final class AppBootstrapper {
    private let runtimeOptions: AppRuntimeOptions
    private let starterRetryCooldown: TimeInterval = 20
    private var hasPreparedLocalState = false
    private var hasLoadedRemoteStarters = false
    private var isRefreshingRemoteStarters = false
    private var nextStarterRefreshRetryAt: Date = .distantPast

    init(runtimeOptions: AppRuntimeOptions = .current) {
        self.runtimeOptions = runtimeOptions
    }

    func bootstrap(
        modelContext: ModelContext,
        messageService: MessageService
    ) async {
        if !hasPreparedLocalState {
            seedPersonas(into: modelContext)
            seedCurrentUserProfile(into: modelContext)
            seedSystemContacts(into: modelContext)
            if runtimeOptions.shouldBootstrapBundledMoments {
                seedPengyouMoments(into: modelContext)
            }
            syncContentGraph(into: modelContext)
            if runtimeOptions.shouldApplyDemoInviteOrder {
                forceDemoInviteOrder(into: modelContext)
            }
            hasPreparedLocalState = true
        }

        do {
            try messageService.prepareThreads(modelContext: modelContext)
        } catch {
            return
        }

        guard !hasLoadedRemoteStarters else { return }
        guard !isRefreshingRemoteStarters else { return }
        guard Date() >= nextStarterRefreshRetryAt else { return }

        let contacts = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []
        guard contacts.contains(where: { $0.relationshipStatusValue == .accepted && $0.linkedPersonaId != nil }) else {
            return
        }

        isRefreshingRemoteStarters = true
        let outcome = await messageService.refreshStarterMessages(
            modelContext: modelContext,
            userInterests: CurrentUserProfileStore.selectedInterests(in: modelContext)
        )
        isRefreshingRemoteStarters = false

        if outcome.didLoadRemoteData {
            hasLoadedRemoteStarters = true
            nextStarterRefreshRetryAt = .distantPast
        } else {
            nextStarterRefreshRetryAt = Date().addingTimeInterval(starterRetryCooldown)
        }
    }
}
