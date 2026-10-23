import SwiftUI

extension View {
    @ViewBuilder
    func loopGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 28))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
    }
}
