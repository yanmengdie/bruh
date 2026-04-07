import SwiftUI

struct PersonaAvatar: View {
    let imageName: String
    let size: CGFloat

    init(imageName: String, size: CGFloat = 44) {
        self.imageName = imageName
        self.size = size
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}
