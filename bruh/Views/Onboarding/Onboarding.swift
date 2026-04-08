import SwiftUI

struct Onboarding: View {
    @State private var name = ""
    @State private var selectedInterests: Set<OnboardingInterest> = OnboardingInterestStore.load()
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        ZStack {
            AppTheme.messagesBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 76)

                header

                Spacer()
                    .frame(height: 24)

                avatarsCluster

                Spacer()
                    .frame(height: 32)

                nameSection

                Spacer()
                    .frame(height: 24)

                interestsSection

                Spacer(minLength: 44)

                ctaSection
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
        }
        .onAppear {
            isNameFieldFocused = true
            OnboardingInterestStore.save(selectedInterests)
        }
        .onChange(of: selectedInterests) { _, newValue in
            OnboardingInterestStore.save(newValue)
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            Text("BRUH")
                .font(.system(size: 72, weight: .black))
                .italic()
                .foregroundStyle(Color(red: 0.10, green: 0.11, blue: 0.13))
                .tracking(1)

            Text("News from your bruh.")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color(red: 0.57, green: 0.57, blue: 0.57))
        }
    }

    private var avatarsCluster: some View {
        ZStack {
            HStack(spacing: -9) {
                avatar(color: Color(red: 0.84, green: 0.17, blue: 0.22), emoji: "🧑🏻")
                avatar(color: Color(red: 0.13, green: 0.18, blue: 0.61), emoji: "👩🏻")
                avatar(color: Color(red: 0.10, green: 0.67, blue: 0.56), emoji: "🧑🏽")
                avatar(color: Color(red: 0.75, green: 0.57, blue: 0.04), emoji: "👩🏼")
                avatar(color: Color(red: 0.95, green: 0.41, blue: 0.14), emoji: "👩🏽")
            }

            bubble(text: "Fake news! 🗣️", textColor: Color(red: 0.85, green: 0.24, blue: 0.30))
                .offset(x: -74, y: -38)

            bubble(text: "To Mars 🚀", textColor: Color(red: 0.35, green: 0.36, blue: 0.60))
                .offset(x: -38, y: 26)

            bubble(text: "AGI soon 🧠", textColor: Color(red: 0.07, green: 0.64, blue: 0.52))
                .offset(x: 82, y: -34)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("WHAT'S YOUR NAME, BRUH?")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.15))

            TextField("Bruh", text: $name)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isNameFieldFocused)
                .textFieldStyle(.plain)
            .padding(.horizontal, 20)
            .frame(height: 76)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WHAT ARE YOU INTO?")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.15))

            interestChip(.politics)

            HStack(spacing: 16) {
                interestChip(.entertainment)
                interestChip(.sports)
            }

            HStack(spacing: 16) {
                interestChip(.finance)
                interestChip(.tech)
            }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 16) {
            Button(action: {}) {
                Text("Meet your bruhs ➔")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.10, green: 0.10, blue: 0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Text("By continuing you agree to bruh's Terms of Service")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color(red: 0.74, green: 0.74, blue: 0.74))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 10)
        }
    }

    private func avatar(color: Color, emoji: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 72, height: 72)
            .overlay(
                Text(emoji)
                    .font(.system(size: 40))
            )
    }

    private func bubble(text: String, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func interestChip(_ interest: OnboardingInterest) -> some View {
        let isSelected = selectedInterests.contains(interest)

        return Button {
            toggleInterest(interest)
        } label: {
            HStack(spacing: 10) {
                Text(interest.emoji)
                    .font(.system(size: 18))

                Text(interest.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)

                if interest.isHot {
                    Text("HOT")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.86, green: 0.23, blue: 0.28))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.96, green: 0.87, blue: 0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.leading, 10)
                }
            }
            .foregroundStyle(isSelected ? Color(red: 0.12, green: 0.13, blue: 0.15) : Color(red: 0.43, green: 0.43, blue: 0.45))
            .padding(.horizontal, 20)
            .frame(height: 57)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color.white.opacity(isSelected ? 0.72 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color(red: 0.13, green: 0.14, blue: 0.16), lineWidth: 2.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(interest.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func toggleInterest(_ interest: OnboardingInterest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }
}

#Preview {
    Onboarding()
}

enum OnboardingInterest: String, CaseIterable, Hashable {
    case politics
    case entertainment
    case sports
    case finance
    case tech

    var title: String {
        switch self {
        case .politics: return "Politics"
        case .entertainment: return "Entertainment"
        case .sports: return "Sports"
        case .finance: return "Finance"
        case .tech: return "Tech"
        }
    }

    var emoji: String {
        switch self {
        case .politics: return "🏛️"
        case .entertainment: return "🎬"
        case .sports: return "⚽️"
        case .finance: return "💰"
        case .tech: return "🤖"
        }
    }

    var isHot: Bool {
        self == .politics || self == .tech
    }
}

enum OnboardingInterestStore {
    static let userDefaultsKey = "onboarding.selectedInterestTopics"
    private static let defaultSelection: Set<OnboardingInterest> = [.politics, .sports, .tech]

    static func load(userDefaults: UserDefaults = .standard) -> Set<OnboardingInterest> {
        guard let raw = userDefaults.string(forKey: userDefaultsKey), !raw.isEmpty else {
            return defaultSelection
        }

        let values = raw
            .split(separator: ",")
            .compactMap { OnboardingInterest(rawValue: String($0)) }

        return values.isEmpty ? defaultSelection : Set(values)
    }

    static func save(_ selection: Set<OnboardingInterest>, userDefaults: UserDefaults = .standard) {
        let serialized = selection
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")

        userDefaults.set(serialized, forKey: userDefaultsKey)
    }
}
