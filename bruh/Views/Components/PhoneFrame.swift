import SwiftUI

/// 模拟手机外壳组件，包含状态栏、灵动岛和 Home Indicator
struct PhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 54, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 30, y: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 50, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                        .padding(1)
                }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .fill(Color(.systemBackground))
                    .padding(5)

                VStack(spacing: 0) {
                    statusBar
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .zIndex(1)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    homeIndicator
                        .padding(.bottom, 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                .padding(5)

                dynamicIsland
                    .padding(.top, 10)
            }
        }
        .aspectRatio(9 / 19.5, contentMode: .fit)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private var dynamicIsland: some View {
        Capsule()
            .fill(.black)
            .frame(width: 126, height: 34)
            .overlay {
                Circle()
                    .fill(Color(red: 0.14, green: 0.14, blue: 0.14))
                    .frame(width: 10, height: 10)
                    .offset(x: 38)
            }
    }

    private var statusBar: some View {
        HStack {
            Text(currentTime, style: .time)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                    .font(.system(size: 13))
                Image(systemName: "wifi")
                    .font(.system(size: 14))
                Image(systemName: "battery.100")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
            }
            .foregroundStyle(.primary)
        }
    }

    private var homeIndicator: some View {
        Capsule()
            .fill(Color.primary.opacity(0.28))
            .frame(width: 134, height: 5)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.black, .gray], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

        PhoneFrame {
            Color.blue.opacity(0.1)
                .overlay(Text("手机桌面"))
        }
        .padding(40)
    }
}
