//
//  BattleEngine.swift
//  ARApp
//

/// バトルのルール（攻撃・ダメージ・勝敗）。状態を受け取って書き換えるだけで、タイマーや画面、通信は持たない
/// 自分の行動も相手の行動も同じ apply を通すので、どちらの端末で計算しても同じ結果になる
enum BattleEngine {
    /// 2 人とも同じ HP で始める
    static let maxHP = 300
    static let normalAttackDamage = 10
    /// 通常攻撃のクールダウン（秒）。連打の制限は入力した端末で行うので、状態には持たない
    static let normalAttackCooldown: Double = 0.3
    /// 通常攻撃が当たるたびに溜まる必殺技ゲージ
    static let specialGaugeGain = 10
    static let specialAttackDamage = 50

    /// attacker が action を行う。当たれば与えたダメージを返し、決着後やゲージ不足で行えなければ nil を返す
    static func apply(_ action: BattleAction, by attacker: FighterID, to state: inout BattleState) -> Int? {
        guard state.winner == nil,
              var me = state.fighters[attacker],
              let targetID = state.opponentID(of: attacker),
              var target = state.fighters[targetID]
        else { return nil }

        let damage: Int
        switch action {
        case .normalAttack:
            damage = min(normalAttackDamage, target.hp)
            me.specialGauge = min(me.specialGauge + specialGaugeGain, Fighter.specialGaugeMax)
        case .specialAttack:
            guard me.canUseSpecial else { return nil }
            damage = min(specialAttackDamage, target.hp)
            me.specialGauge = 0
        }

        target.hp -= damage
        state.fighters[attacker] = me
        state.fighters[targetID] = target
        if target.hp == 0 {
            state.winner = attacker
        }
        return damage
    }
}
