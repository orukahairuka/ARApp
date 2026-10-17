# ARApp

SwiftUI + ARKit + RealityKit で作る iOS 向け AR モンスター捕獲アプリ。
マップ上でモンスターを選び、AR 画面で捕獲する。将来は ESP32 の BLE RSSI で近接判定を行う。

## 開発の進め方

- Step 単位で段階的に実装する。
- ユーザーは ARKit / RealityKit を学習中。実装後は変更ファイルと役割、実機での確認手順を説明する。
- 不要な抽象化や複雑な設計は避ける。状態やロジックが生まれた時点で必要な層を追加する。
- ハッカソン用のため、ユニットテストや UI テストは書かない。画面に動作確認用のボタンなども置かない。動作はプレビューと実機で確認する。
- 開発中だけ使うコード（テスト用の見た目、RSSI の表示、ダミー実装など）は、ファイル先頭に「⚠️ 開発用」と目立つコメントを書き、削除するときに一緒に消す場所も書いておく。
- 使われていないコードは残さず削除する。
- コミットメッセージは日本語で書く。

## アーキテクチャ：MVVM + Service 層

```
ARApp/
├── App/          エントリポイント（ARAppApp.swift）
├── Models/       データ定義のみ（例：Monster）。UI やフレームワークに依存しない
│   └── Battle/   バトルの中だけで使うデータ（行動の種類、戦う人の HP やゲージなど）
├── Logic/        ゲームのルール（例：BattleEngine）。状態を受け取って計算するだけで、UI・タイマー・通信は持たない
├── ViewModels/   画面の状態とロジック（@Observable）
├── Views/        SwiftUI の View。ContentView 以外は機能ごとのフォルダに置く
│   ├── Map/      マップ画面（屋内マップ、現在地）
│   ├── Capture/  AR 捕獲画面
│   │   └── AR/   ARView まわり（RealityKit / ARKit を扱うのはここだけ）
│   └── Battle/   バトル画面（タップで攻撃し合うリアルタイムバトル）
├── Services/     外部とのやり取り（BLE / RSSI、Supabase での対戦）
└── Resources/    アプリに同梱するファイル
    └── Models/   モンスターの 3D モデル（USDZ）。Kenney「Cube Pets」（CC0）を OBJ から変換したもの
```

### Views/Capture/AR の責務分担

| ファイル | 担当 |
|---|---|
| `ARViewContainer` | SwiftUI と ARView の橋渡し（`UIViewRepresentable`）、AR セッションの run / pause |
| `ARSceneController` | アンカーやエンティティの配置、タップなどシーンのイベントを ViewModel に伝える |
| `MonsterEntity` など | 3D の見た目を作るだけ。配置する場所やタイミングは決めない |

`ARSceneController` は `UIViewRepresentable` の Coordinator として使う（`makeCoordinator()` の戻り値）。
SwiftUI の決まりとしての名前ではなく、役割がわかる名前を付けている。

空のフォルダは作らない。最初のファイルが必要になった時点でフォルダを作る。

### フォルダの分け方

iOS に慣れていないメンバーでも目的のファイルを見つけやすいように、次のように分ける。

- **Views は機能ごとのフォルダに分ける**（`Map/`、`Capture/`、`Battle/`）。新しい画面を作るときは、その機能のフォルダを作って置く。
- **Models は、1 つの機能の中だけで使うデータが多いときだけ、機能名のフォルダにまとめる**（例：`Models/Battle/`）。`Monster` や `Location` のように複数の画面で使うデータは `Models/` 直下に置く。
- **ViewModels は分けない。** ファイル数が少なく、名前でどの画面用かわかるため。

### ルール

- **ViewModel は `@Observable` クラス**で実装する（`ObservableObject` は使わない）。
- **ViewModel に `ARView` や `UIView` などの UIKit オブジェクトを持たせない。**
  - ViewModel は「どのモンスターを出すか」「捕獲状態」などの状態だけを持つ。
  - 3D エンティティの配置、アンカー、タップ検知など ARView の命令的な操作は `ARSceneController` が担当する。
  - ARView 側から ViewModel への通知は `ARSceneController` 経由で行う。
- **ViewModel の状態は `private(set)` にし、外からはメソッドを呼んで変更する。** 状態を変えるのは ViewModel 自身だけにする。
- **Service は protocol で定義し、ViewModel に外から渡す。**
  - ESP32 がなくてもダミー実装で開発やテストができるようにするため。
- **View の部品は、必要になった時点で切り出す。** 使い回す予定のない部品を先回りして作らない。
  - body が長くなったら、同じファイル内の `private struct` に分ける（例：`IndoorMapComponent` の `LocationMarkerComponent`）。
  - 部品が増えて 1 ファイルが長くなったら（目安 200 行）、その機能のフォルダ内の別ファイルに分ける（例：`Views/Battle/` の `StatBarComponent`）。
  - 同じ見た目を 2 つ以上の画面で使うようになったら、`Views/Components/` に共通の View として切り出す。1 か所でしか使わないうちは切り出さない。
- **`ContentView` はタブを並べるだけ**にする。「AR に対応した端末か」など画面ごとの判定は、その画面の View の中で行う。
- **画面をまたいで使う状態は `ContentView` で 1 つだけ作り、各画面に渡す。** 例：現在地の `LocationViewModel` はマップ画面と捕獲画面で共有する。画面ごとに作ると推定が別々に動き、現在地が食い違う。
- **同じデータを複数の型に重複して持たせない。** 例：地点の ID・名前・マップ上の位置・フィンガープリントはすべて `Location` にまとめる。
- **SwiftUI の View の名前は、画面なら `〜View`、UI の部品なら `〜Component` で終える。** ファイル名も型の名前に合わせる。
  - 画面：`ContentView` と、そのタブに置く 1 画面ぶんの View（例：`MapView`、`ARCaptureView`、`BattleView`）。
  - 部品：画面の中に置く View。ボタン、ゲージ、カード、HP バー、マーカーなど（例：`IndoorMapComponent`、`StatBarComponent`、`BattleResultComponent`）。`private struct` で同じファイルに置く部品も同じ。
  - `ARViewContainer` は `UIViewRepresentable` の橋渡し役なので例外。
- AR セッションのライフサイクル（`run` / `pause`）は `ARViewContainer` で管理する（`makeUIView` で run、`dismantleUIView` で pause）。
  - **`TabView` の中で AR を使う画面は、表示中だけ `ARViewContainer` を置く**（`onAppear` / `onDisappear` で表示中かを持つ。例：`ARCaptureView`）。`TabView` は別のタブに切り替えても画面を残すので、そのままでは `dismantleUIView` が呼ばれず、カメラが動き続ける。

## プロジェクト設定

- Xcode のファイルシステム同期グループを使っているため、`ARApp/` 配下にファイルを置けば自動でターゲットに含まれる（pbxproj の編集は不要）。
- Info.plist は自動生成（`GENERATE_INFOPLIST_FILE = YES`）。キーを追加するときは pbxproj の `INFOPLIST_KEY_*` ビルド設定を使う。
- デプロイメントターゲットは iOS 26.2。デフォルトのアクター隔離は `MainActor`。
- AR は実機でのみ動作する。シミュレータでは非対応メッセージが表示される。
- 対戦は Supabase（Swift Package `supabase-swift`）でやり取りする。テーブルと関数の定義はリポジトリ直下の `supabase/schema.sql`。
  - 接続先（URL と anon key）は `Resources/SupabaseSecrets.plist` に書く。公開リポジトリなので `.gitignore` 済みで、コミットしない。ひな形は `supabase/SupabaseSecrets.example.plist`。
  - plist がない・値が空なら、CPU が相手になる `DummyBattleService` を使う。
  - `service_role`（secret）の鍵はアプリにもリポジトリにも入れない。

## ビルド確認

```sh
xcodebuild -project ARApp.xcodeproj -scheme ARApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

エディタの SourceKit が `UIViewRepresentable` などについて誤ったエラーを出すことがあるが、iOS 向けにビルドできれば問題ない。
