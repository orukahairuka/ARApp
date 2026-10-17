//
//  SupabaseBattleService.swift
//  ARApp
//

import Foundation
import Supabase

/// Supabase で対戦相手とやり取りする
/// テーブルと関数の定義は リポジトリ直下の supabase/schema.sql にある
/// - 相手探し：join_battle 関数を呼ぶ。待っている人がいれば入り、いなければ部屋を作って待つ
/// - 行動：battle_actions テーブルに 1 回ずつ番号（seq）を付けて書き込み、相手の書き込みを Realtime で受け取る
///   相手の行動は番号順に流す。Realtime がつながらない・取りこぼしたときは、2 秒ごとにデータベースを直接見て取り直す
/// - 決着：finish_battle 関数で勝った人を記録する。2 人とも記録しようとしたら、先に記録した方に決まる
final class SupabaseBattleService: BattleService {
    enum ServiceError: Error {
        /// 部屋を作って待っても、相手が来なかった
        case noOpponent
        /// 相手の行動が一定時間届かない、または相手が対戦をやめた
        case opponentLeft
        /// 届いたモンスター名や行動が、アプリの知らない値だった
        case invalidData
        /// 参加中の対戦がないのに、行動を受け取ろうとした・決着を記録しようとした
        case notInBattle
        /// 自分の行動を送れなかった。相手の端末と HP が食い違うので、対戦を続けられない
        case sendFailed
    }

    /// 部屋を作ってからこの時間待っても相手が来なければ、あきらめる（秒）
    /// join_battle は 2 分より古い部屋を使わないので、それより少し短くする
    private static let matchingTimeout: TimeInterval = 110
    /// 相手の行動がこの時間届かなければ、相手がいなくなったとみなす（秒）
    private static let opponentTimeout: TimeInterval = 60
    /// 書き込みに失敗したとき、何回まで試すか
    private static let attempts = 3
    /// Realtime を取りこぼしたときのために、データベースを直接見に行く間隔（秒）
    private static let fallbackFetchInterval: TimeInterval = 2

    private let client: SupabaseClient
    /// 自分を見分ける ID。ログインは使わず、アプリを起動するたびに作り直す
    private let playerID = UUID()

    /// 参加中の対戦の ID
    private var battleID: UUID?
    /// 相手が入ってきたら入る、相手のプレイヤー ID とモンスター名
    private var opponentPlayerID: UUID?
    private var opponentMonsterName: String?
    /// 参加中の対戦の変更を受け取る Realtime のチャンネル
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    /// 対戦が終わった（相手がやめた、またはどちらかが決着を記録した）
    private var isBattleFinished = false
    /// 記録された勝者。相手がやめて終わったときは nil
    private var winnerID: UUID?

    /// 相手の行動を流す先。opponentActions() を呼んでから、流し終わるまである
    private var continuation: AsyncThrowingStream<BattleAction, Error>.Continuation?
    private var watchTask: Task<Void, Never>?
    /// 届いたがまだ流していない相手の行動（番号ごと）。番号が飛んでいたら、間が届くまで待つ
    private var pendingActions: [Int: BattleAction] = [:]
    /// 最後に流した相手の行動の番号（1 から）
    private var lastDeliveredSeq = 0
    /// 最後に相手の行動が届いた時刻。相手がいなくなったかの判断に使う
    private var lastReceivedAt = Date.now

    /// 書き込みが終わっていない自分の行動（古い順）
    private var outgoing: [ActionRow] = []
    /// 次に送る自分の行動の番号
    private var nextSeq = 1
    private var sendTask: Task<Void, Never>?
    private var didFailToSend = false

    init(url: URL, anonKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    func findOpponent(locationID: String, monster: Monster) async throws -> Monster {
        await leave()
        do {
            return try await joinAndWait(locationID: locationID, monster: monster)
        } catch {
            // キャンセルされたり失敗したりしたら、作った部屋が相手待ちのまま残らないように片付ける
            // キャンセルされた Task の中で通信すると通信まで取り消されるので、別の Task で片付けて終わるのを待つ
            await Task { await leave() }.value
            throw error
        }
    }

    /// join_battle で部屋に入り（または作り）、相手がそろうまで待つ
    private func joinAndWait(locationID: String, monster: Monster) async throws -> Monster {
        // 途中でキャンセルされても通信は最後まで行い、部屋の ID を受け取ってから片付けられるようにする
        // （通信ごと取り消すと、サーバーには部屋ができたのに ID がわからず消せなくなる）
        let params = JoinBattleParams(locationID: locationID, playerID: playerID, monster: monster.modelName)
        let row: BattleRow = try await Task { [client] in
            try await client.rpc("join_battle", params: params).execute().value
        }.value
        battleID = row.id
        try Task.checkCancellation()

        if row.player1ID == playerID {
            receive(row)
        } else {
            opponentPlayerID = row.player1ID
            opponentMonsterName = row.player1Monster
        }
        startListening(battleID: row.id)

        // 自分が部屋を作った場合は、相手が入ってくるまで待つ
        // Realtime を取りこぼしたときのために、ときどきデータベースも直接見る（購読を始める前に入ってきた場合もここで気づく）
        let deadline = Date.now.addingTimeInterval(Self.matchingTimeout)
        var nextFetch = Date.now
        while opponentMonsterName == nil {
            guard Date.now < deadline else { throw ServiceError.noOpponent }
            if Date.now >= nextFetch {
                // 通信が一瞬切れても失敗にせず、次の確認を待つ
                if let battle = try? await fetchBattle(id: row.id) {
                    receive(battle)
                }
                nextFetch = Date.now.addingTimeInterval(Self.fallbackFetchInterval)
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        guard let name = opponentMonsterName, let opponent = Monster.named(name) else {
            throw ServiceError.invalidData
        }
        return opponent
    }

    func opponentActions() -> AsyncThrowingStream<BattleAction, Error> {
        let (stream, continuation) = AsyncThrowingStream<BattleAction, Error>.makeStream()
        guard let battleID else {
            continuation.finish(throwing: ServiceError.notInBattle)
            return stream
        }
        self.continuation = continuation
        lastReceivedAt = .now
        // 受け取る側が止まったら（決着した、対戦をやめた）、データベースを見に行くのもやめる
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.endActions() }
        }

        // 流し始める前に Realtime で届いていた行動を流す
        deliverPendingActions()
        if isBattleFinished {
            Task { await endAfterLastActions() }
        } else {
            watchTask = Task { [weak self] in await self?.watch(battleID: battleID) }
        }
        return stream
    }

    func send(_ action: BattleAction) {
        guard let battleID else { return }
        outgoing.append(ActionRow(battleID: battleID, playerID: playerID, seq: nextSeq, action: action.rawValue))
        nextSeq += 1
        if sendTask == nil {
            sendTask = Task { await flush() }
        }
    }

    func finish(iWon: Bool) async throws -> Bool {
        guard let battleID, let opponentPlayerID else { throw ServiceError.notInBattle }
        // とどめの行動より先に決着が相手に伝わらないよう、行動を送り終えてから記録する
        await sendTask?.value
        if didFailToSend { throw ServiceError.sendFailed }

        let params = FinishBattleParams(battleID: battleID, winnerID: iWon ? playerID : opponentPlayerID)
        let winner: UUID? = try await retrying { [client] in
            try await client.rpc("finish_battle", params: params).execute().value
        }
        return winner == playerID
    }

    func leave() async {
        // 先に状態を空にしてから通信する。通信を待っている間に次の相手探しが始まっても、新しい対戦に触れないようにする
        let leavingBattleID = battleID
        let leavingChannel = channel
        listenTask?.cancel()
        listenTask = nil
        channel = nil
        sendTask?.cancel()
        sendTask = nil
        endActions()
        battleID = nil
        opponentPlayerID = nil
        opponentMonsterName = nil
        isBattleFinished = false
        winnerID = nil
        pendingActions = [:]
        lastDeliveredSeq = 0
        outgoing = []
        nextSeq = 1
        didFailToSend = false

        if let leavingChannel {
            await client.removeChannel(leavingChannel)
        }
        // 相手待ちの部屋が残らないように、対戦を終わったことにする。対戦中なら相手にも伝わる
        // 決着がついたあとなら、記録された勝者はそのまま残る
        if let leavingBattleID {
            let params = FinishBattleParams(battleID: leavingBattleID, winnerID: nil)
            _ = try? await client.rpc("finish_battle", params: params).execute()
        }
    }

    // MARK: - 自分の行動を送る

    /// 書き込みが終わっていない行動を、古い順にまとめて書き込む
    /// 書き込んでいる間に増えた行動は、次の回でまとめて書き込む
    private func flush() async {
        while !outgoing.isEmpty {
            let rows = outgoing
            do {
                // 書き込めたのに返事だけ届かなかった場合に備えて、同じ番号の行がすでにあれば何もしない（ON CONFLICT DO NOTHING）
                try await retrying { [client] in
                    try await client
                        .from("battle_actions")
                        .upsert(rows, onConflict: "battle_id,player_id,seq", ignoreDuplicates: true)
                        .execute()
                }
            } catch {
                // 対戦をやめた（leave でキャンセルされた）ときは、もう何もしない
                guard !Task.isCancelled else { return }
                didFailToSend = true
                outgoing = []
                endActions(throwing: ServiceError.sendFailed)
                break
            }
            guard !Task.isCancelled else { return }
            outgoing.removeFirst(rows.count)
        }
        sendTask = nil
    }

    /// 通信が一瞬切れても対戦が終わらないように、少し待ってやり直す
    private func retrying<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < Self.attempts, !Task.isCancelled else { throw error }
                attempt += 1
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - 相手の行動と対戦の変更を受け取る

    /// 対戦の変更（相手が入った・終わった）と、相手の行動を Realtime で受け取り始める
    /// 購読はバックグラウンドで行い、終わるのを待たない
    /// 会場の Wi-Fi などで Realtime（WebSocket）がつながらなくても、データベースの定期確認で代わりに受け取れるので対戦は続けられる
    private func startListening(battleID: UUID) {
        let channel = client.channel("battle-\(battleID.uuidString)")
        // 受け取りたい変更は、購読を始める前に登録しておく
        let battleUpdates = channel.postgresChange(
            UpdateAction.self, table: "battles", filter: .eq("id", value: battleID)
        )
        let actionInserts = channel.postgresChange(
            InsertAction.self, table: "battle_actions", filter: .eq("battle_id", value: battleID)
        )
        // 購読の途中で対戦をやめても leave() で閉じられるよう、先に持っておく
        self.channel = channel

        listenTask = Task { [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                // 【開発用】原因を調べるためのログ。リリースするときに消してよい
                print("Realtime に接続できませんでした。データベースの定期確認だけで続けます: \(error)")
                return
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await update in battleUpdates {
                        guard let row = try? update.decodeRecord(as: BattleRow.self, decoder: JSONDecoder()) else { continue }
                        self?.receive(row)
                    }
                }
                group.addTask { @MainActor in
                    for await insert in actionInserts {
                        guard let row = try? insert.decodeRecord(as: ActionRow.self, decoder: JSONDecoder()) else { continue }
                        self?.receive(row)
                    }
                }
            }
        }
    }

    /// Realtime で届かなかった行動や、相手がいなくなったことに気づけるように、ときどきデータベースを直接見る
    private func watch(battleID: UUID) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.fallbackFetchInterval))
            guard !Task.isCancelled else { return }
            // 通信が一瞬切れても失敗にせず、次の確認を待つ（相手がいなくなったかはタイムアウトで判断する）
            try? await fetchOpponentActions(battleID: battleID)
            if let battle = try? await fetchBattle(id: battleID) {
                receive(battle)
            }
            if !isBattleFinished, Date.now.timeIntervalSince(lastReceivedAt) > Self.opponentTimeout {
                endActions(throwing: ServiceError.opponentLeft)
                return
            }
        }
    }

    /// やめた対戦の通信が遅れて届くことがあるので、参加中の対戦のものだけ受け取る
    private func receive(_ row: BattleRow) {
        guard row.id == battleID else { return }
        if row.player1ID == playerID, let name = row.player2Monster {
            opponentPlayerID = row.player2ID
            opponentMonsterName = name
        }
        guard row.status == "finished", !isBattleFinished else { return }
        isBattleFinished = true
        winnerID = row.winnerID
        // 行動を流している途中なら、残りを流してから終える。まだ流し始めていなければ、opponentActions() で終える
        if continuation != nil {
            Task { await endAfterLastActions() }
        }
    }

    private func receive(_ row: ActionRow) {
        guard row.battleID == battleID, row.playerID != playerID,
              row.seq > lastDeliveredSeq, pendingActions[row.seq] == nil else { return }
        // 知らない行動を飛ばして先へ進むと、相手の端末と HP が食い違うので、対戦を続けない
        guard let action = BattleAction(rawValue: row.action) else {
            endActions(throwing: ServiceError.invalidData)
            return
        }
        pendingActions[row.seq] = action
        lastReceivedAt = .now
        deliverPendingActions()
    }

    /// 次の番号の行動から順に流す。番号が飛んでいたら、そこで止めて間が届くのを待つ
    private func deliverPendingActions() {
        guard let continuation else { return }
        while let action = pendingActions.removeValue(forKey: lastDeliveredSeq + 1) {
            lastDeliveredSeq += 1
            continuation.yield(action)
        }
    }

    /// 対戦が終わったら、残っている相手の行動を流してから終える
    /// 相手は行動を送り終えてから決着を記録するが、Realtime で取りこぼしていた場合に備えて、もう一度だけデータベースを見る
    private func endAfterLastActions() async {
        guard let endingBattleID = battleID else { return }
        try? await fetchOpponentActions(battleID: endingBattleID)
        // 確認している間に対戦をやめて次の対戦が始まっていたら、新しい対戦を終わらせない
        guard battleID == endingBattleID else { return }
        if winnerID == nil {
            endActions(throwing: ServiceError.opponentLeft)
        } else {
            endActions()
        }
    }

    /// 相手の行動を流すのをやめる。何度呼んでもよい
    private func endActions(throwing error: Error? = nil) {
        watchTask?.cancel()
        watchTask = nil
        continuation?.finish(throwing: error)
        continuation = nil
    }

    private func fetchBattle(id: UUID) async throws -> BattleRow {
        try await client.from("battles").select().eq("id", value: id).single().execute().value
    }

    private func fetchOpponentActions(battleID: UUID) async throws {
        let rows: [ActionRow] = try await client
            .from("battle_actions")
            .select()
            .eq("battle_id", value: battleID)
            .neq("player_id", value: playerID)
            .gt("seq", value: lastDeliveredSeq)
            .order("seq")
            .execute()
            .value
        rows.forEach(receive)
    }
}

// MARK: - テーブルの行と関数の引数（supabase/schema.sql と対応する）

nonisolated private struct BattleRow: Decodable, Sendable {
    let id: UUID
    let status: String
    let player1ID: UUID
    let player1Monster: String
    let player2ID: UUID?
    let player2Monster: String?
    let winnerID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, status
        case player1ID = "player1_id"
        case player1Monster = "player1_monster"
        case player2ID = "player2_id"
        case player2Monster = "player2_monster"
        case winnerID = "winner_id"
    }
}

nonisolated private struct ActionRow: Codable, Sendable {
    let battleID: UUID
    let playerID: UUID
    let seq: Int
    let action: String

    enum CodingKeys: String, CodingKey {
        case battleID = "battle_id"
        case playerID = "player_id"
        case seq, action
    }
}

nonisolated private struct JoinBattleParams: Encodable, Sendable {
    let locationID: String
    let playerID: UUID
    let monster: String

    enum CodingKeys: String, CodingKey {
        case locationID = "p_location_id"
        case playerID = "p_player_id"
        case monster = "p_monster"
    }
}

/// winnerID が nil のときは p_winner_id を送らない（関数側の既定値 null になる）
nonisolated private struct FinishBattleParams: Encodable, Sendable {
    let battleID: UUID
    let winnerID: UUID?

    enum CodingKeys: String, CodingKey {
        case battleID = "p_battle_id"
        case winnerID = "p_winner_id"
    }
}
