import SwiftUI

/// Карточка разблокировки Mac — в стиле карточек зарядки и подключения устройств.
/// Замок на карточке закрытый и «отщёлкивается» в открытый, следом выскакивает галочка.
struct WakeView: View {
    @ViewState private var unlocked = false
    @ViewState private var done = false

    var body: some View {
        HStack(spacing: 22) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(unlocked ? 0 : -14))
                    .scaleEffect(unlocked ? 1 : 0.85)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.green)
                    .offset(x: 10, y: -8)
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)
            }
            .frame(width: 92, height: 80)
            .opacity(unlocked ? 1 : 0)
            .scaleEffect(unlocked ? 1 : 0.9)

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Разблокировано"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
                Text("MacBook")
                    .font(.system(size: 17, weight: .bold))
                Text(L("С возвращением"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            // Замок немного постоит закрытым, чтобы анимация читалась.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.75, dampingFraction: 0.52)) {
                    unlocked = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                    done = true
                }
            }
        }
    }
}
