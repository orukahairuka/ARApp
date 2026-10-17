//
//  SupabaseConfig.swift
//  ARApp
//

import Foundation

/// Supabase プロジェクトの接続先
/// 値は Resources/SupabaseSecrets.plist から読む。公開リポジトリに鍵を載せないよう、このファイルは .gitignore に入れている
/// ひな形は リポジトリ直下の supabase/SupabaseSecrets.example.plist。コピーして、ダッシュボードの値を書く
/// - URL：Project Settings → Data API の Project URL（例："https://xxxx.supabase.co"）
/// - AnonKey：Project Settings → API Keys の Legacy タブにある anon（public）key。service_role（secret）は入れない
enum SupabaseConfig {
    private static let values: [String: String] = {
        guard let fileURL = Bundle.main.url(forResource: "SupabaseSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return values
    }()

    static let url = values["URL"] ?? ""
    static let anonKey = values["AnonKey"] ?? ""

    /// plist がない・値が空なら、ContentView は DummyBattleService を使う
    static var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }
}
