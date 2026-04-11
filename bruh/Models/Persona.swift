import Foundation
import SwiftData

enum ContactRelationshipStatus: String, CaseIterable {
    case locked
    case pending
    case accepted
    case ignored
    case custom
}

@Model
final class Persona {
    @Attribute(.unique) var id: String
    var displayName: String
    var avatarName: String
    var handle: String
    var domains: [String]
    var stance: String
    var triggerKeywords: [String]
    var xUsername: String
    var subtitle: String
    var inviteMessage: String
    var themeColorHex: String
    var locationLabel: String
    var inviteOrder: Int

    init(
        id: String,
        displayName: String,
        avatarName: String,
        handle: String,
        domains: [String],
        stance: String,
        triggerKeywords: [String],
        xUsername: String,
        subtitle: String,
        inviteMessage: String,
        themeColorHex: String,
        locationLabel: String,
        inviteOrder: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarName = avatarName
        self.handle = handle
        self.domains = domains
        self.stance = stance
        self.triggerKeywords = triggerKeywords
        self.xUsername = xUsername
        self.subtitle = subtitle
        self.inviteMessage = inviteMessage
        self.themeColorHex = themeColorHex
        self.locationLabel = locationLabel
        self.inviteOrder = inviteOrder
    }
}

extension Persona {
    static var all: [Persona] {
        PersonaCatalog.all.map { $0.makePersona() }
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var bruhHandle: String
    @Attribute(.externalStorage) var avatarImageData: Data?
    var selectedInterestIds: [String]
    var timezoneIdentifier: String
    var onboardingCompletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = CurrentUserProfileStore.userId,
        displayName: String = "You",
        bruhHandle: String = "@yourboi",
        avatarImageData: Data? = nil,
        selectedInterestIds: [String] = NewsInterest.defaultSelection.map(\.rawValue),
        timezoneIdentifier: String = TimeZone.current.identifier,
        onboardingCompletedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.bruhHandle = bruhHandle
        self.avatarImageData = avatarImageData
        self.selectedInterestIds = selectedInterestIds
        self.timezoneIdentifier = timezoneIdentifier
        self.onboardingCompletedAt = onboardingCompletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Contact {
    @Attribute(.unique) var id: UUID
    var linkedPersonaId: String?
    var name: String
    var phoneNumber: String
    var email: String
    var avatarName: String
    var themeColorHex: String
    var locationLabel: String
    var isFavorite: Bool
    var relationshipStatus: String
    var inviteOrder: Int?
    var acceptedAt: Date?
    var ignoredAt: Date?
    var affinityScore: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        linkedPersonaId: String? = nil,
        name: String,
        phoneNumber: String,
        email: String = "",
        avatarName: String = "Avatar",
        themeColorHex: String = "#3B82F6",
        locationLabel: String = "",
        isFavorite: Bool = false,
        relationshipStatus: String = ContactRelationshipStatus.custom.rawValue,
        inviteOrder: Int? = nil,
        acceptedAt: Date? = nil,
        ignoredAt: Date? = nil,
        affinityScore: Double = 0.5,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.linkedPersonaId = linkedPersonaId
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.avatarName = avatarName
        self.themeColorHex = themeColorHex
        self.locationLabel = locationLabel
        self.isFavorite = isFavorite
        self.relationshipStatus = relationshipStatus
        self.inviteOrder = inviteOrder
        self.acceptedAt = acceptedAt
        self.ignoredAt = ignoredAt
        self.affinityScore = affinityScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Contact {
    var relationshipStatusValue: ContactRelationshipStatus {
        get { ContactRelationshipStatus(rawValue: relationshipStatus) ?? .custom }
        set { relationshipStatus = newValue.rawValue }
    }

    var isVisibleInContactsList: Bool {
        switch relationshipStatusValue {
        case .accepted, .custom:
            return true
        case .locked, .pending, .ignored:
            return false
        }
    }

    var isPendingInvitation: Bool {
        linkedPersonaId != nil && relationshipStatusValue == .pending
    }
}
