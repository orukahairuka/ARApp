//
//  Fighter.swift
//  ARApp
//

/// バトルの状態の中で、戦う人を見分ける ID
typealias FighterID = String

/// バトルで戦う 1 人ぶんの状態。自分も相手も同じ形で持つ
struct Fighter {
    static let specialGaugeMax = 100

    let id: FighterID
    let name: String
    let maxHP: Int
    var hp: Int
    /// 必殺技ゲージ（0〜specialGaugeMax）
    var specialGauge = 0

    init(id: FighterID, name: String, maxHP: Int) {
        self.id = id
        self.name = name
        self.maxHP = maxHP
        hp = maxHP
    }

    /// ゲージが満タンなら必殺技を使える
    var canUseSpecial: Bool { specialGauge >= Fighter.specialGaugeMax }
}
