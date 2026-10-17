//
//  MonsterEntity.swift
//  ARApp
//

import RealityKit

/// モンスターの 3D の見た目を作る
/// 担当：見た目だけ。配置する場所やタイミングは ARSceneController が決める
enum MonsterEntity {
    /// モンスターの 3D モデル（USDZ）を読み込み、`monster.size` の大きさに合わせる
    /// ファイルの読み込みには時間がかかるので async になっている
    static func make(from monster: Monster) async -> Entity {
        do {
            let model = try await Entity(named: monster.modelName)

            // モデルは 1〜2m の大きさで作られているので、一番長い辺が size になるように縮小する
            // 原点は足元にあるので、そのまま床の上に乗る
            let longestSide = model.visualBounds(relativeTo: nil).extents.max()
            if longestSide > 0 {
                model.scale = .init(repeating: monster.size / longestSide)
            }
            return model
        } catch {
            // 【開発用】原因を調べるためのログ。リリースするときに消してよい
            print("モデル \(monster.modelName) を読み込めませんでした: \(error)")
            // 開発用の球体。PlaceholderMonsterEntity.swift を消すときは `return Entity()` に置き換える
            return PlaceholderMonsterEntity.make(size: monster.size)
        }
    }
}
