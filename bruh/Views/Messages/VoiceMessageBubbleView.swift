import SwiftUI

struct VoiceMessageBubbleView: View {
    let themeColor: Color
    let isPlaying: Bool
    let isLoading: Bool
    let progress: Double
    let duration: TimeInterval?

    private let waveformHeights: [CGFloat] = [10, 15, 21, 13, 19, 25, 15, 11, 18, 24, 16, 12, 20, 27, 17, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(themeColor.opacity(0.18))
                        .frame(width: 42, height: 42)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(themeColor)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(themeColor)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                }

                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(waveformHeights.enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(barColor(for: index))
                            .frame(width: 4, height: height)
                    }
                }

                Text(durationText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeColor.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: themeColor.opacity(0.08), radius: 8, y: 4)
    }

    private func barColor(for index: Int) -> Color {
        let activeBars = max(Int(round(progress * Double(waveformHeights.count))), isPlaying || isLoading ? 1 : 6)
        if index < activeBars {
            return themeColor.opacity(isPlaying ? 0.92 : (isLoading ? 0.74 : 0.62))
        }
        return Color.black.opacity(0.14)
    }

    private var durationText: String {
        guard let duration, duration > 0, duration.isFinite else { return "0:00" }
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
