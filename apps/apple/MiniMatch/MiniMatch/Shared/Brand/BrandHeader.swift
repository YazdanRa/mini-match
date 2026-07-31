import SwiftUI

struct BrandHeader: View {
    var compact = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroFontSize = 64

    var body: some View {
        VStack(spacing: compact ? -6 : -10) {
            Text("Mini")
                .foregroundStyle(MiniMatchColors.coralBrand)
            Text("Match")
                .foregroundStyle(MiniMatchColors.blueText)
        }
        .font(compact ? .title : .system(size: heroFontSize))
        .fontWeight(.black)
        .fontDesign(.rounded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mini Match")
    }
}

#Preview {
    BrandHeader()
}
