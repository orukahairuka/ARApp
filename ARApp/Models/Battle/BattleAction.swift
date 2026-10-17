//
//  BattleAction.swift
//  ARApp
//

/// バトル中に取れる行動。オンライン対戦では、この rawValue を相手に送る（battle_actions テーブルの action 列）
enum BattleAction: String {
    case normalAttack
    case specialAttack
}
