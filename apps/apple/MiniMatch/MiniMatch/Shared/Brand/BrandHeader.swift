import SwiftUI

struct BrandHeader: View {
    var compact = false
    var accessibilityIdentifier = "brand-header"
    @ScaledMetric(relativeTo: .largeTitle) private var heroFontSize = 78

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
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mini Match")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#Preview {
    BrandHeader()
}
