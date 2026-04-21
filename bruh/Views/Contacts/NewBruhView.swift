import SwiftUI
import UIKit

struct BruhInvitation: Identifiable, Hashable {
    let personaId: String
    let displayName: String
    let handle: String
    let subtitle: String
    let inviteMessage: String
    let avatarEmoji: String
    let avatarColor: Color
    let themeHex: String
    let avatarName: String
    let phoneNumber: String
    let email: String
    let location: String

    var id: String { personaId }

    static func == (lhs: BruhInvitation, rhs: BruhInvitation) -> Bool {
        lhs.personaId == rhs.personaId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(personaId)
    }

    init(persona: Persona, contact: Contact) {
        self.personaId = persona.id
        self.handle = persona.handle
        self.avatarName = persona.avatarName
        self.phoneNumber = contact.phoneNumber
        self.email = contact.email
        self.location = contact.locationLabel

        if persona.id == "justin_sun" {
            self.displayName = "孙割"
            self.subtitle = "孙宇晨 · 波场 TRON 创始人"
            self.inviteMessage = "鸽们，来一起冲。链上机会转瞬即逝，我会第一时间把最有价值的信号同步给你，别错过。🚀"
            self.avatarEmoji = "🧑‍💼"
            self.avatarColor = Color(red: 0.11, green: 0.74, blue: 0.63)
            self.themeHex = "#19BCA0"
        } else {
            let fallbackColor = AppTheme.color(from: persona.themeColorHex, fallback: .gray)
            self.displayName = persona.displayName
            self.subtitle = persona.subtitle
            self.inviteMessage = persona.inviteMessage
            self.avatarEmoji = Self.avatarEmoji(for: persona.id)
            self.avatarColor = fallbackColor
            self.themeHex = persona.themeColorHex
        }
    }

    private static func avatarEmoji(for personaId: String) -> String {
        switch personaId {
        case "trump":
            return "🧑‍💼"
        case "musk":
            return "👨‍🚀"
        case "sam_altman":
            return "🤖"
        case "zhang_peng":
            return "🎙️"
        case "lei_jun":
            return "📱"
        case "影石刘靖康":
            return "📷"
        case "luo_yonghao":
            return "🎤"
        case "justin_sun":
            return "🪙"
        case "kim_kardashian":
            return "✨"
        case "papi":
            return "🎬"
        case "kobe_bryant":
            return "🏀"
        case "cristiano_ronaldo":
            return "⚽️"
        default:
            return "👤"
        }
    }
}

struct NewBruhView: View {
    @Environment(\.dismiss) private var dismiss

    let invitation: BruhInvitation
    let lockedCandidateNames: [String]
    let onAccept: (BruhInvitation) -> Void
    let onIgnore: (BruhInvitation) -> Void
    private var invitationThemeColor: Color {
        AppTheme.color(from: invitation.themeHex, fallback: invitation.avatarColor)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if UIImage(named: "Bell") != nil {
                        Image("Bell")
                            .resizable()
                            .scaledToFit()
                    } else {
                        Text("🔔")
                            .font(.system(size: 40))
                    }
                }
                .frame(width: 60, height: 60)
                    .padding(.top, 10)

                VStack(spacing: 6) {
                    Text("你收到一个鸽们请求！")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                    Text("有位重要的人想和你聊聊。")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.40))
                }

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        invitationAvatar

                        VStack(alignment: .leading, spacing: 2) {
                            Text(invitation.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.9))
                            Text("\(invitation.handle) · \(invitation.subtitle)")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.38))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }

                    ZStack {
                        Text(invitation.inviteMessage)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.86))
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(invitationThemeColor)
                                        .offset(x: -3, y: 0)

                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(AppTheme.messageBubbleBase)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Button {
                            onAccept(invitation)
                        } label: {
                            Text("接受请求 ✓")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.black.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onIgnore(invitation)
                        } label: {
                            Text("暂时不了")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.black.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                if !lockedCandidateNames.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("还有更多鸽们想认识你")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.35))
                            .tracking(2)

                        HStack(spacing: 14) {
                            ForEach(Array(lockedCandidateNames.prefix(5)), id: \.self) { name in
                                lockedCandidate(name: name, color: Color.black.opacity(0.12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 18)

                (
                    Text("接受 ").foregroundStyle(Color.black.opacity(0.26))
                    + Text(invitation.displayName.components(separatedBy: " ").first ?? invitation.displayName).fontWeight(.bold)
                    + Text(" 后会解锁更多联系人").foregroundStyle(Color.black.opacity(0.26))
                )
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.messagesBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AppBackButton(action: { dismiss() })
            }
        }
        .enableUnifiedSwipeBack()
    }

    private var invitationAvatar: some View {
        Circle()
            .fill(invitation.avatarColor)
            .frame(width: 76, height: 76)
            .overlay {
                if !invitation.avatarName.isEmpty, UIImage(named: invitation.avatarName) != nil {
                    Image(invitation.avatarName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                } else {
                    Text(invitation.avatarEmoji)
                        .font(.system(size: 36))
                }
            }
    }

    private func lockedCandidate(name: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 56, height: 56)
                .overlay {
                    Text("🔒")
                        .font(.system(size: 24))
                }

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.24))
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationStack {
        NewBruhView(
            invitation: BruhInvitation(
                persona: PersonaCatalog.trump.makePersona(),
                contact: Contact(
                    linkedPersonaId: "trump",
                    name: "Donald Trump",
                    phoneNumber: "+1 561 555 0145",
                    email: "donald@truthsocial.com",
                    avatarName: "Avatar_Trump",
                    themeColorHex: "#D62839",
                    locationLabel: "United States",
                    relationshipStatus: ContactRelationshipStatus.pending.rawValue,
                    inviteOrder: 0
                )
            ),
            lockedCandidateNames: ["Elon Musk", "Sam Altman"],
            onAccept: { _ in },
            onIgnore: { _ in }
        )
    }
}
