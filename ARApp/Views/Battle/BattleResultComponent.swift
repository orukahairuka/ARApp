//
//  BattleResultComponent.swift
//  ARApp
//

import SwiftUI

/// 勝敗を全面に出し、ロビーに戻るボタンを置く。下の画面へのタップも遮る
struct BattleResultComponent: View {
    let outcome: BattleViewModel.Outcome
    let opponentName: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: outcome == .won ? "crown.fill" : "xmark.octagon.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(outcome == .won ? .yellow : .red)
                Text(outcome == .won ? "勝利！" : "敗北…")
                    .font(.largeTitle.bold())
                Text(outcome == .won ? "\(opponentName)に勝った！" : "\(opponentName)に負けてしまった…")
                Button("ロビーに戻る", systemImage: "arrow.uturn.backward", action: onBack)
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

#Preview {
    BattleResultComponent(outcome: .won, opponentName: "ライオン") {}
}
