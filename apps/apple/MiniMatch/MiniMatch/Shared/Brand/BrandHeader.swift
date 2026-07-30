import SwiftUI

struct BrandHeader: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? -6 : -10) {
            Text("Mini")
                .foregroundStyle(MiniMatchColors.coralBrand)
            Text("Match")
                .foregroundStyle(MiniMatchColors.blueText)
        }
        .font(compact ? .title : .largeTitle)
        .fontWeight(.black)
        .fontDesign(.rounded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mini Match")
    }
}

#Preview {
    BrandHeader()
}
