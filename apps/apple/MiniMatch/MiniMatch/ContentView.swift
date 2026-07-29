import SwiftUI

struct ContentView: View {
    let model: GameModel

    var body: some View {
        @Bindable var model = model

        ZStack {
            MiniMatchColors.background
                .ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    MiniMatchColors.navy
                        .frame(height: geometry.safeAreaInsets.top)
                    Spacer()
                }
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            switch model.screen {
            case .home:
                HomeView(model: model)
            case .lobby:
                LobbyView(model: model)
            case .result:
                ResultView(model: model)
            }
        }
        .tint(MiniMatchColors.blue)
        .preferredColorScheme(.light)
        .alert(
            "Couldn’t continue",
            isPresented: $model.isShowingError,
            actions: { Button("OK") {} },
            message: { Text(model.errorMessage) }
        )
    }
}
