import SwiftUI

extension Network {
    var icon: Image {
        Image(imageName).renderingMode(.template)
    }
}

struct NetworkIcon: View {
    let network: Network
    var size: CGFloat = 16

    var body: some View {
        network.icon
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
