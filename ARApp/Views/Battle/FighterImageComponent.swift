//
//  FighterImageComponent.swift
//  ARApp
//
//  ⚠️⚠️⚠️ 仮の見た目 ⚠️⚠️⚠️
//  モンスターの絵や 3D モデルをバトル画面に出せるようになったら、この部品ごと置き換える。
//  使っている場所：BattleView（自分と相手）と BattleLobbyComponent（自分）
//  どちらのモンスターでも同じアイコン（自分は盾、相手は炎）になっている
//

import SwiftUI

/// 【仮】モンスターの代わりに出す SF Symbols のアイコン
struct FighterImageComponent: View {
    let systemName: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(color)
            .padding(24)
            .background(color.opacity(0.15), in: Circle())
    }
}

#Preview {
    FighterImageComponent(systemName: "flame.fill", color: .orange, size: 120)
}
