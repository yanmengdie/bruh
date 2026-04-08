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
        displayName: "马期克",
        handle: "@elonmusk",
        subtitle: "CEO · SpaceX · xAI",
        inviteMessage: "你很有想法。想第一时间获取 AI、火箭和新品发布的关键信息吗？聊聊。🚀",
        avatarEmoji: "👨‍🚀",
        avatarColor: Color(red: 0.20, green: 0.35, blue: 0.74),
        themeHex: "#1F2A8A",
        avatarName: "Avatar_ Elon",
        phoneNumber: "+1 310 555 0142",
        email: "elon@x.ai",
        location: "X HQ"
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
        avatarName: "Avatar_Justin Sun",
        phoneNumber: "+86 138 0000 8888",
        email: "justin@tron.network",
        location: "新加坡"
    )

    static let papi = BruhInvitation(
        personaId: "papi",
        displayName: "Hahi",
        handle: "@papi",
        subtitle: "热梗雷达 · 氛围组扛把子",
        inviteMessage: "bro 你加我一下。我这边每天都有几个爆点，我只发最有意思的那条。",
        avatarEmoji: "🕶️",
        avatarColor: Color(red: 0.10, green: 0.12, blue: 0.16),
        themeHex: "#111827",
        avatarName: "Avatar_Papi",
        phoneNumber: "+1 212 555 0199",
        email: "papi@bruh.app",
        location: "New York"
    )

    static let samAltman = BruhInvitation(
        personaId: "sam_altman",
        displayName: "凹凸曼",
        handle: "@sama",
        subtitle: "OpenAI · 产品与趋势",
        inviteMessage: "Hey — if you want, I can share concise updates on what’s actually changing in AI.",
        avatarEmoji: "🤖",
        avatarColor: Color(red: 0.10, green: 0.66, blue: 0.53),
        themeHex: "#1AA987",
        avatarName: "Avatar_ Sam Altman",
        phoneNumber: "+1 415 555 0124",
        email: "sam@openai.com",
        location: "San Francisco"
    )

    static let leiJun = BruhInvitation(
        personaId: "lei_jun",
        displayName: "田车",
        handle: "@leijun",
        subtitle: "小米 · 创始人",
        inviteMessage: "兄弟，加个好友。我给你发最关键的产品和行业判断，少走弯路。",
        avatarEmoji: "📱",
        avatarColor: Color(red: 1.0, green: 0.41, blue: 0.0),
        themeHex: "#FF6900",
        avatarName: "Avatar_ Leijun",
        phoneNumber: "+86 10 5555 0202",
        email: "leijun@xiaomi.com",
        location: "北京"
    )

    static let sunYuchen = BruhInvitation(
        personaId: "sun_yuchen",
        displayName: "孙割",
        handle: "@sunyuchen",
        subtitle: "TRON · 链上节奏",
        inviteMessage: "bro，信息差就是机会。加了我，我只发有用的信号。",
        avatarEmoji: "🚀",
        avatarColor: Color(red: 0.11, green: 0.74, blue: 0.63),
        themeHex: "#19BCA0",
        avatarName: "Avatar_Justin Sun",
        phoneNumber: "+86 10 5555 0303",
        email: "sun@tron.network",
        location: "新加坡"
    )

    static let liuJingkang = BruhInvitation(
        personaId: "liu_jingkang",
        displayName: "刘瞬间",
        handle: "@insta360",
        subtitle: "Insta360 · 影像与硬件",
        inviteMessage: "聊聊影像和硬件。你关心的参数、体验、供应链，我给你一句话说清楚。",
        avatarEmoji: "📷",
        avatarColor: Color(red: 0.96, green: 0.62, blue: 0.11),
        themeHex: "#F59E0B",
        avatarName: "Avatar_ LiuJingkang",
        phoneNumber: "+86 755 5555 0404",
        email: "liu@insta360.com",
        location: "深圳"
    )

    static let kimKardashian = BruhInvitation(
        personaId: "kim_kardashian",
        displayName: "银卡戴珊",
        handle: "@kimkardashian",
        subtitle: "生活方式 · 热点名流",
        inviteMessage: "Hi love. I’ll send you the highlights, not the drama.",
        avatarEmoji: "💅",
        avatarColor: Color(red: 0.93, green: 0.30, blue: 0.62),
        themeHex: "#EC4899",
        avatarName: "Avatar_ Kim",
        phoneNumber: "+1 310 555 0505",
        email: "kim@bruh.app",
        location: "Los Angeles"
    )

    static let luoYonghao = BruhInvitation(
        personaId: "luo_yonghao",
        displayName: "老罗",
        handle: "@luoyonghao",
        subtitle: "老罗 · 吐槽与产品",
        inviteMessage: "我跟你说，很多东西就是——一眼假。加了我，有离谱的我第一时间告诉你。",
        avatarEmoji: "🎤",
        avatarColor: Color(red: 0.94, green: 0.27, blue: 0.26),
        themeHex: "#EF4444",
        avatarName: "Avatar_LuoYonghao",
        phoneNumber: "+86 10 5555 0606",
        email: "luo@bruh.app",
        location: "北京"
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
                        lockedCandidate(name: "马期克", color: Color(red: 0.46, green: 0.45, blue: 0.61))
                        lockedCandidate(name: "凹凸曼", color: Color(red: 0.43, green: 0.70, blue: 0.62))
                        lockedCandidate(name: "孙割", color: Color(red: 0.72, green: 0.62, blue: 0.36))
                        lockedCandidate(name: "田车", color: Color(red: 0.78, green: 0.54, blue: 0.41))
                        lockedCandidate(name: "银卡戴珊", color: Color(red: 0.74, green: 0.44, blue: 0.57))
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
