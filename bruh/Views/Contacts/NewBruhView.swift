import SwiftUI

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

    static let trump = BruhInvitation(
        personaId: "trump",
        displayName: "Donald Trump",
        handle: "@realdonaldtrump",
        subtitle: "45th & 47th POTUS",
        inviteMessage: "Hey bruh! I heard you're interested in politics. GREAT choice. Nobody knows politics better than me. Accept this and I'll keep you updated on everything. Believe me. ☝️🇺🇸",
        avatarEmoji: "🧑‍💼",
        avatarColor: Color(red: 0.84, green: 0.15, blue: 0.24),
        themeHex: "#D62839",
        avatarName: "avatar_trump",
        phoneNumber: "+1 561 555 0145",
        email: "donald@truthsocial.com",
        location: "United States"
    )

    static let musk = BruhInvitation(
        personaId: "musk",
        displayName: "Elon Musk",
        handle: "@elonmusk",
        subtitle: "CEO · SpaceX · xAI",
        inviteMessage: "You seem sharp. Want first access to what matters in AI, rockets, and product launches? Let’s talk. 🚀",
        avatarEmoji: "👨‍🚀",
        avatarColor: Color(red: 0.20, green: 0.35, blue: 0.74),
        themeHex: "#1F2A8A",
        avatarName: "avatar_musk",
        phoneNumber: "+1 310 555 0142",
        email: "elon@x.ai",
        location: "X HQ"
    )

    static let zuckerberg = BruhInvitation(
        personaId: "zuckerberg",
        displayName: "Mark Zuckerberg",
        handle: "@finkd",
        subtitle: "Meta · AI & Social",
        inviteMessage: "I can send you concise updates on social platforms, AI releases, and what creators are reacting to in real time. 🤝",
        avatarEmoji: "🧑‍💻",
        avatarColor: Color(red: 0.42, green: 0.35, blue: 0.88),
        themeHex: "#6A5AE0",
        avatarName: "avatar_zuckerberg",
        phoneNumber: "+1 650 555 0108",
        email: "mark@meta.com",
        location: "Meta Park"
    )
}

struct NewBruhView: View {
    @Environment(\.dismiss) private var dismiss

    let invitation: BruhInvitation
    let onAccept: (BruhInvitation) -> Void
    private var invitationThemeColor: Color {
        AppTheme.color(from: invitation.themeHex, fallback: invitation.avatarColor)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("🔔")
                    .font(.system(size: 40))
                    .padding(.top, 10)

                VStack(spacing: 6) {
                    Text("You got a bruh request!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                    Text("Someone important wants to talk to you.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.40))
                }

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(invitation.avatarColor)
                            .frame(width: 76, height: 76)
                            .overlay {
                                Text(invitation.avatarEmoji)
                                    .font(.system(size: 36))
                            }

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

                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(invitationThemeColor)
                            .frame(width: 5)

                        Text(invitation.inviteMessage)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.86))
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(invitationThemeColor.opacity(0.18))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack(spacing: 12) {
                        Button {
                            onAccept(invitation)
                            dismiss()
                        } label: {
                            Text("Accept bruh ✓")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.black.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismiss()
                        } label: {
                            Text("Later")
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

                VStack(alignment: .leading, spacing: 14) {
                    Text("MORE BRUHS WANT TO CONNECT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .tracking(2)

                    HStack(spacing: 14) {
                        lockedCandidate(name: "Elon Musk", color: Color(red: 0.46, green: 0.45, blue: 0.61))
                        lockedCandidate(name: "Sam Altmar", color: Color(red: 0.43, green: 0.70, blue: 0.62))
                        lockedCandidate(name: "Xi Jinping", color: Color(red: 0.72, green: 0.62, blue: 0.36))
                        lockedCandidate(name: "雷军", color: Color(red: 0.78, green: 0.54, blue: 0.41))
                        lockedCandidate(name: "Taylor Swift", color: Color(red: 0.74, green: 0.44, blue: 0.57))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 18)

                (
                    Text("Accept ").foregroundStyle(Color.black.opacity(0.26))
                    + Text(invitation.displayName.components(separatedBy: " ").first ?? invitation.displayName).fontWeight(.bold)
                    + Text(" to unlock more bruhs").foregroundStyle(Color.black.opacity(0.26))
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AppBackButton(action: { dismiss() })
            }
        }
        .enableUnifiedSwipeBack()
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
        NewBruhView(invitation: .trump, onAccept: { _ in })
    }
}
