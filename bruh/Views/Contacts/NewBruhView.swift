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

    static let trump = BruhInvitation(
        personaId: "trump",
        displayName: "Donald Trump",
        handle: "@realdonaldtrump",
        subtitle: "第45任与第47任美国总统",
        inviteMessage: "嘿，bro！我听说你关注政治，选得太对了。没有人比我更懂政治。接受这次请求，我会把最重要的动态第一时间发给你。相信我。☝️🇺🇸",
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
        inviteMessage: "你很有想法。想第一时间获取 AI、火箭和新品发布的关键信息吗？聊聊。🚀",
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
        subtitle: "Meta · AI 与社交",
        inviteMessage: "我可以给你推送社交平台、AI 发布以及创作者实时反馈的精简更新。🤝",
        avatarEmoji: "🧑‍💻",
        avatarColor: Color(red: 0.42, green: 0.35, blue: 0.88),
        themeHex: "#6A5AE0",
        avatarName: "avatar_zuckerberg",
        phoneNumber: "+1 650 555 0108",
        email: "mark@meta.com",
        location: "Meta Park"
    )

    static let justinSun = BruhInvitation(
        personaId: "justin_sun",
        displayName: "孙割",
        handle: "@justinsuntron",
        subtitle: "孙宇晨 · 波场 TRON 创始人",
        inviteMessage: "bro，来一起冲。链上机会转瞬即逝，我会第一时间把最有价值的信号同步给你，别错过。🚀",
        avatarEmoji: "🧑‍💼",
        avatarColor: Color(red: 0.11, green: 0.74, blue: 0.63),
        themeHex: "#19BCA0",
        avatarName: "Justin Sun",
        phoneNumber: "+86 138 0000 8888",
        email: "justin@tron.network",
        location: "新加坡"
    )
}

struct NewBruhView: View {
    @Environment(\.dismiss) private var dismiss

    let invitation: BruhInvitation
    let onAccept: (BruhInvitation) -> Void
    let onIgnore: (BruhInvitation) -> Void
    private var invitationThemeColor: Color {
        AppTheme.color(from: invitation.themeHex, fallback: invitation.avatarColor)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("Bell")
                    .resizable()
                    .scaledToFit()
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
                            dismiss()
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
                            dismiss()
                        } label: {
                            Text("不了")
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
                    Text("更多鸽们想和你建立联系")
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
                    Text("接受 ").foregroundStyle(Color.black.opacity(0.26))
                    + Text(invitation.displayName.components(separatedBy: " ").first ?? invitation.displayName).fontWeight(.bold)
                    + Text(" 以解锁更多鸽们").foregroundStyle(Color.black.opacity(0.26))
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

    private var invitationAvatar: some View {
        Circle()
            .fill(invitation.avatarColor)
            .frame(width: 76, height: 76)
            .overlay {
                if UIImage(named: invitation.avatarName) != nil {
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
}

#Preview {
    NavigationStack {
        NewBruhView(invitation: .trump, onAccept: { _ in }, onIgnore: { _ in })
    }
}
