//
//  ContentView.swift
//  ARApp
//
//  Created by Sakurai Erika on 2026/10/08.
//

import SwiftUI

struct ContentView: View {
    /// 現在地の推定はアプリ全体で 1 つだけ動かし、各画面で共有する
    @State private var locationViewModel = LocationViewModel(scanner: Self.makeScanner())
    @State private var battleService = Self.makeBattleService()

    var body: some View {
        TabView {
            Tab("マップ", systemImage: "map.fill") {
                MapView(locationViewModel: locationViewModel)
            }
            Tab("捕獲", systemImage: "camera.viewfinder") {
                ARCaptureView(locationViewModel: locationViewModel)
            }
            Tab("バトル", systemImage: "bolt.fill") {
                BattleView(locationViewModel: locationViewModel, service: battleService)
            }
        }
        .onAppear { locationViewModel.start() }
        .onDisappear { locationViewModel.stop() }
    }

    /// シミュレータには Bluetooth がないので、ダミーのビーコンで「入口」にいることにする
    private static func makeScanner() -> any BeaconScanner {
        #if targetEnvironment(simulator)
        DummyBeaconScanner()
        #else
        BLEBeaconScanner()
        #endif
    }

    /// SupabaseConfig に接続先が書いてあれば Supabase で対戦し、なければ CPU が相手になるダミーを使う
    /// 【開発用】ここで DummyBattleService を使うのは開発中だけ。リリースするときは SupabaseBattleService だけにする
    /// （DummyBattleService のクラス自体は BattleView の #Preview で使うので残す）
    private static func makeBattleService() -> any BattleService {
        if SupabaseConfig.isConfigured, let url = URL(string: SupabaseConfig.url) {
            SupabaseBattleService(url: url, anonKey: SupabaseConfig.anonKey)
        } else {
            DummyBattleService()
        }
    }
}

#Preview {
    ContentView()
}
