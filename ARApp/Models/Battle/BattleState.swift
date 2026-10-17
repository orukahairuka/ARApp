//
//  BattleState.swift
//  ARApp
//

/// バトル全体の状態。自分の行動も相手の行動も同じルールで反映できるよう、「自分」「敵」ではなく ID で持つ
struct BattleState {
    var fighters: [FighterID: Fighter]
    /// 勝った人の ID。決着がついていなければ nil
    var winner: FighterID?

    /// 1 対 1 のバトルを始める
    init(_ first: Fighter, _ second: Fighter) {
        fighters = [first.id: first, second.id: second]
    }

    /// id の人の対戦相手の ID
    func opponentID(of id: FighterID) -> FighterID? {
        fighters.keys.first { $0 != id }
    }
}
