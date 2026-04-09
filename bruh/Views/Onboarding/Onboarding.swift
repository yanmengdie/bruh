import SwiftUI
import UIKit
import SwiftData

struct Onboarding: View {
    @Environment(\.modelContext) private var modelContext
    let onComplete: () -> Void

    @State private var name = ""
    @State private var selectedInterests: Set<OnboardingInterest> = OnboardingInterestStore.load()
    @State private var profileImage: UIImage?
    @State private var isPresentingImagePicker = false
    @State private var isShowingImageSourceOptions = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickerAlertTitle = ""
    @State private var pickerAlertMessage = ""
    @State private var isShowingPickerAlert = false
    @FocusState private var isNameFieldFocused: Bool

    init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

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
        .confirmationDialog("选择头像", isPresented: $isShowingImageSourceOptions, titleVisibility: .visible) {
            Button("拍照") {
                presentImagePicker(sourceType: .camera)
            }

            Button("从相册选择") {
                presentImagePicker(sourceType: .photoLibrary)
            }

            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingImagePicker) {
            OnboardingImagePicker(
                image: $profileImage,
                sourceType: imagePickerSourceType
            )
                .ignoresSafeArea()
        }
        .alert(pickerAlertTitle, isPresented: $isShowingPickerAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(pickerAlertMessage)
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            Text("BRUH")
                .font(.system(size: 72, weight: .black))
                .italic()
                .foregroundStyle(Color(red: 0.10, green: 0.11, blue: 0.13))
                .tracking(1)

            Text("来自你鸽们的消息。")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color(red: 0.57, green: 0.57, blue: 0.57))
        }
    }

    private var avatarsCluster: some View {
        ZStack {
            HStack(spacing: -9) {
                avatar(
                    color: Color(red: 0.84, green: 0.17, blue: 0.22),
                    assetName: "Avatar_Trump",
                    fallbackEmoji: "🧑🏻"
                )
                avatar(
                    color: Color(red: 0.13, green: 0.18, blue: 0.61),
                    assetName: "Avatar_Elon",
                    fallbackEmoji: "👩🏻"
                )
                avatar(
                    color: Color(red: 1.00, green: 0.41, blue: 0.00),
                    assetName: "Avatar_Leijun",
                    fallbackEmoji: "🧑🏽"
                )
                avatar(
                    color: Color(red: 0.06, green: 0.12, blue: 0.22),
                    assetName: "Avatar_Sam Altman",
                    fallbackEmoji: "👩🏼"
                )
                avatar(
                    color: Color(red: 0.88, green: 0.11, blue: 0.55),
                    assetName: "Avatar_Kim",
                    fallbackEmoji: "👩🏽"
                )
            }

            bubble(text: "假新闻！🗣️", textColor: Color(red: 0.85, green: 0.24, blue: 0.30))
                .offset(x: -74, y: -38)

            bubble(text: "去火星 🚀", textColor: Color(red: 0.35, green: 0.36, blue: 0.60))
                .offset(x: -38, y: 26)

            bubble(text: "AGI 快来了 🧠", textColor: Color(red: 0.07, green: 0.64, blue: 0.52))
                .offset(x: 82, y: -34)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("你叫什么，鸽们？")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.15))

            HStack(spacing: 16) {
                avatarPickerButton

                TextField("请输入昵称", text: $name)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isNameFieldFocused)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(minHeight: 132)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var avatarPickerButton: some View {
        Button {
            isShowingImageSourceOptions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(red: 0.90, green: 0.88, blue: 0.84))
                    .frame(width: 108, height: 108)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 5, dash: [10, 5]))
                    }
                    .overlay {
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                        } else {
                            Text("📸")
                                .font(.system(size: 50))
                        }
                    }

                Circle()
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.13))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 4, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择头像")
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你感兴趣什么？")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.15))

            HStack(spacing: 16) {
                interestChip(.politics)
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
            Button(action: completeOnboarding) {
                Text("去认识你的鸽们 ➔")
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
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

            Text("继续即表示你同意 bruh 的服务条款")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color(red: 0.74, green: 0.74, blue: 0.74))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 10)
        }
    }

    private func avatar(color: Color, assetName: String, fallbackEmoji: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 72, height: 72)
            .overlay {
                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                } else {
                    Text(fallbackEmoji)
                        .font(.system(size: 40))
                }
            }
    }

    private func bubble(text: String, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.86))
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
                    Text("热门")
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
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }

    private func toggleInterest(_ interest: OnboardingInterest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }

    private func presentImagePicker(sourceType: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            switch sourceType {
            case .camera:
                pickerAlertTitle = "当前设备无法打开相机"
                pickerAlertMessage = "请在支持相机的设备上重试，或改为从相册选择。"
            case .photoLibrary, .savedPhotosAlbum:
                pickerAlertTitle = "当前设备无法访问相册"
                pickerAlertMessage = "请检查系统权限后重试。"
            @unknown default:
                pickerAlertTitle = "当前设备无法选择图片"
                pickerAlertMessage = "请稍后重试。"
            }
            isShowingPickerAlert = true
            return
        }

        imagePickerSourceType = sourceType
        isPresentingImagePicker = true
    }

    private func completeOnboarding() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let sortedInterestIds = selectedInterests
            .map(\.rawValue)
            .sorted()

        CurrentUserProfileStore.updateSelectedInterests(sortedInterestIds, in: modelContext)
        CurrentUserProfileStore.completeOnboardingProfile(
            displayName: trimmedName,
            avatarImageData: profileImage?.jpegData(compressionQuality: 0.85),
            in: modelContext
        )
        onComplete()
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
        case .politics: return "政治"
        case .entertainment: return "娱乐"
        case .sports: return "体育"
        case .finance: return "财经"
        case .tech: return "科技"
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
        self == .tech
    }
}

enum OnboardingInterestStore {
    static let userDefaultsKey = "onboarding.selectedInterestTopics"
    private static let defaultSelection: Set<OnboardingInterest> = [.sports, .tech]

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

private struct OnboardingImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = sourceType
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var image: UIImage?
        private let dismiss: DismissAction

        init(image: Binding<UIImage?>, dismiss: DismissAction) {
            _image = image
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let editedImage = info[.editedImage] as? UIImage {
                image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                image = originalImage
            }
            dismiss()
        }
    }
}
