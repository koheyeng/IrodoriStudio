import Foundation

/// Python の常駐ワーカー（`python/irodori_worker.py`、PROTOCOL.md 参照）に繋いで本物の音声合成をする実装。
///
/// `Process` で Python を起動したままにして（モデルを載せっぱなし）、標準入出力で JSON を1行ずつやり取りする。
/// MPS は同時に1本しか生成できないので、呼び出しは actor の中で「物理的にジョブが終わるまで」順番待ちにする
/// （Swift 側の呼び出しがキャンセルされても、Python に投げてしまった1本はそのまま焼き切られる。下記 `synthesize` 参照）。
public actor PythonSpeechSynthesizer: SpeechSynthesizer {
    private let pythonPath: URL
    private let workerScriptPath: URL
    private let outputDirectory: URL
    /// irodori_worker.py が `sys.path` に足す Irodori-TTS リポジトリ（環境変数 IRODORI_TTS_REPO で伝える）
    private let engineRepoPath: URL

    private var process: Process?
    private var stdin: FileHandle?
    private var lineBuffer = LineBuffer()
    /// 落ちたときの表示用に、標準エラーの末尾だけ覚えておく
    private var stderrTail = ""

    private var nextID = 1
    private var calls: [Int: PendingCall] = [:]

    /// 「同時に1本だけ」のゲート。busy な間に来た呼び出しは waiters で順番待ちする
    private var busy = false
    private var waiters: [Waiter] = []

    public init(pythonPath: URL, workerScriptPath: URL, outputDirectory: URL, engineRepoPath: URL) {
        self.pythonPath = pythonPath
        self.workerScriptPath = workerScriptPath
        self.outputDirectory = outputDirectory
        self.engineRepoPath = engineRepoPath
    }

    deinit {
        // 「標準入力を閉じたら片付けて終了する」約束（PROTOCOL.md）にまず乗る。応じなければ terminate で後始末。
        process?.terminationHandler = nil
        try? stdin?.close()
        process?.terminate()
    }

    // MARK: - SpeechSynthesizer

    public func prepare(model: TTSModel) async throws {
        try ensureRunning()
        _ = try await call { id in
            try Self.encodeLine(LoadCommand(id: id, checkpoint: model.repoID))
        }
    }

    public func synthesize(
        _ request: SynthesisRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SynthesisResult {
        try ensureRunning()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let out = outputDirectory.appendingPathComponent(Self.freshFileName(seed: request.seed))

        let event = try await call(progress: progress) { id in
            try Self.encodeLine(SynthesizeCommand(
                id: id,
                out: out.path,
                text: request.text,
                caption: request.caption,
                seed: request.seed,
                refWav: request.referenceAudioURL?.path,
                numSteps: 40,
                durationScale: 1.0
            ))
        }
        guard case .done(_, let path, let duration) = event else {
            throw WorkerError.protocolViolation("synthesize の応答が done ではありませんでした")
        }
        let audioURL = path.map(URL.init(fileURLWithPath:)) ?? out
        return SynthesisResult(audioURL: audioURL, duration: duration ?? 0)
    }

    // MARK: - 起動・プロセス管理

    private func ensureRunning() throws {
        if let process, process.isRunning { return }
        process?.terminationHandler = nil
        process = nil
        stdin = nil

        let proc = Process()
        proc.executableURL = pythonPath
        proc.arguments = [workerScriptPath.path]
        var env = ProcessInfo.processInfo.environment
        env["IRODORI_TTS_REPO"] = engineRepoPath.path
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        lineBuffer = LineBuffer()
        stderrTail = ""

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            Task { await self.consumeStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            Task { await self.consumeStderr(data) }
        }
        proc.terminationHandler = { [weak self] finished in
            Task { await self?.handleTermination(status: finished.terminationStatus) }
        }

        do {
            try proc.run()
        } catch {
            throw WorkerError.launchFailed(reason: error.localizedDescription, stderrTail: "")
        }

        process = proc
        stdin = stdinPipe.fileHandleForWriting
    }

    private func handleTermination(status: Int32) {
        process = nil
        stdin = nil
        let error = WorkerError.crashed(status: status, stderrTail: stderrTail)

        let orphaned = calls
        calls = [:]
        for entry in orphaned.values { entry.continuation?.resume(throwing: error) }

        // ゲート待ちも全部解放する。解放されたものは送信時に「起動していない」で失敗し、
        // 次の呼び出しで ensureRunning() がプロセスを立て直す
        busy = false
        let queued = waiters
        waiters = []
        for waiter in queued { waiter.continuation.resume() }
    }

    // MARK: - 標準出力・標準エラーの取り込み

    private func consumeStdout(_ data: Data) {
        for line in lineBuffer.feed(data) {
            guard !line.isEmpty else { continue }
            if let event = Self.parseEvent(line) {
                handle(event)
            } else {
                FileHandle.standardError.write(Data("[irodori_worker] 想定外の行を無視しました: \(line)\n".utf8))
            }
        }
    }

    private func consumeStderr(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        stderrTail += text
        let limit = 4000
        if stderrTail.count > limit {
            stderrTail = String(stderrTail.suffix(limit))
        }
    }

    private func handle(_ event: WorkerEvent) {
        switch event {
        case .ready:
            break // 起動確認用。特に待ち合わせはしない
        case .log(_, let message):
            FileHandle.standardError.write(Data("[irodori_worker] \(message)\n".utf8))
        case .progress(let id, let value):
            calls[id]?.progress?(value)
        case .done(let id, _, _):
            complete(id: id, result: .success(event))
        case .error(let id, let message):
            complete(id: id, result: .failure(WorkerError.workerReported(message)))
        }
    }

    private func complete(id: Int, result: Result<WorkerEvent, Error>) {
        guard let entry = calls.removeValue(forKey: id) else { return }
        release() // 物理的にジョブが終わったので、待っている次の呼び出しに渡す
        switch result {
        case .success(let event): entry.continuation?.resume(returning: event)
        case .failure(let error): entry.continuation?.resume(throwing: error)
        }
    }

    // MARK: - 呼び出しの直列化（同時に1本だけ）

    private struct PendingCall {
        var continuation: CheckedContinuation<WorkerEvent, Error>?
        var progress: (@Sendable (Double) -> Void)?
    }

    private struct Waiter {
        let token: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private func call(
        progress: (@Sendable (Double) -> Void)? = nil,
        makeLine: (Int) throws -> String
    ) async throws -> WorkerEvent {
        try await acquire()
        let id = nextID
        nextID += 1

        let line: String
        do {
            line = try makeLine(id)
        } catch {
            release()
            throw error
        }

        calls[id] = PendingCall(continuation: nil, progress: progress)
        do {
            try send(line)
        } catch {
            calls[id] = nil
            release()
            throw error
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // send() までは同期実行なので、ここに来た時点で calls[id] はまだ生きている
                calls[id]?.continuation = continuation
            }
        } onCancel: {
            Task { await self.failWaitingForResponse(id: id) }
        }
    }

    private func failWaitingForResponse(id: Int) {
        guard let continuation = calls[id]?.continuation else { return }
        calls[id]?.continuation = nil
        continuation.resume(throwing: CancellationError())
        // release() はしない。Python 側はまだ走っているので、done/error が届くまでゲートは渡さない
        // （ワーカー側にキャンセルの仕組みは無いので、走っている1本はそのまま焼き切られる）
    }

    /// ゲートを取る。busy でなければ即座に、busy ならキャンセル可能な待ち行列に並ぶ
    /// （並んでいる間にキャンセルされれば、Python には一切送らずに投げる）
    private func acquire() async throws {
        if !busy {
            busy = true
            return
        }
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(token: token, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiting(token: token) }
        }
    }

    private func cancelWaiting(token: UUID) {
        guard let index = waiters.firstIndex(where: { $0.token == token }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: ()) // ゲートは busy のまま次へ渡す
        }
    }

    private func send(_ line: String) throws {
        guard let stdin, let process, process.isRunning else {
            throw WorkerError.notRunning(stderrTail: stderrTail)
        }
        var data = Data(line.utf8)
        data.append(0x0A)
        try stdin.write(contentsOf: data)
    }

    // MARK: - ファイル名

    private static func freshFileName(seed: Int) -> String {
        let stamp = fileStamp.string(from: .now)
        return "\(stamp)_seed\(seed)_\(UUID().uuidString.prefix(6)).wav"
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

// MARK: - 行の組み立て・分解（プロセス無しでテストできる部分）

/// stdout からの断片データを行（改行区切り）に組み立てる。行の途中で切れた分は次回まで持ち越す
struct LineBuffer {
    private var carry = Data()

    mutating func feed(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        carry.append(data)
        var lines: [String] = []
        while let newline = carry.firstIndex(of: 0x0A) {
            let lineData = carry[carry.startIndex..<newline]
            lines.append(String(decoding: lineData, as: UTF8.self))
            carry.removeSubrange(carry.startIndex...newline)
        }
        return lines
    }
}

/// Python → Swift の1行分の中身。想定外の行は `parseEvent` が nil を返す
enum WorkerEvent: Equatable {
    case ready
    case log(id: Int, message: String)
    case progress(id: Int, value: Double)
    case done(id: Int, path: String?, duration: Double?)
    case error(id: Int, message: String)
}

extension PythonSpeechSynthesizer {
    /// 受け取った JSON を信用しすぎない: id/event が欠けている・型が合わない・event が未知の行は nil
    static func parseEvent(_ line: String) -> WorkerEvent? {
        guard let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawEvent.self, from: data),
              let event = raw.event else { return nil }
        switch event {
        case "ready":
            return .ready
        case "log":
            guard let id = raw.id, let message = raw.message else { return nil }
            return .log(id: id, message: message)
        case "progress":
            guard let id = raw.id, let value = raw.value else { return nil }
            return .progress(id: id, value: value)
        case "done":
            guard let id = raw.id else { return nil }
            return .done(id: id, path: raw.path, duration: raw.duration)
        case "error":
            guard let id = raw.id, let message = raw.message else { return nil }
            return .error(id: id, message: message)
        default:
            return nil
        }
    }

    struct RawEvent: Decodable {
        let id: Int?
        let event: String?
        let message: String?
        let value: Double?
        let path: String?
        let duration: Double?
    }
}

// MARK: - Swift → Python のコマンド（1行 JSON。改行はしない）

extension PythonSpeechSynthesizer {
    struct LoadCommand: Encodable {
        let id: Int
        let checkpoint: String

        private enum CodingKeys: String, CodingKey { case id, cmd, checkpoint }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode("load", forKey: .cmd)
            try container.encode(checkpoint, forKey: .checkpoint)
        }
    }

    struct SynthesizeCommand: Encodable {
        let id: Int
        let out: String
        let text: String
        let caption: String?
        let seed: Int
        let refWav: String?
        let numSteps: Int
        let durationScale: Double

        private enum CodingKeys: String, CodingKey {
            case id, cmd, out, text, caption, seed
            case refWav = "ref_wav"
            case numSteps = "num_steps"
            case durationScale = "duration_scale"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode("synthesize", forKey: .cmd)
            try container.encode(out, forKey: .out)
            try container.encode(text, forKey: .text)
            if let caption { try container.encode(caption, forKey: .caption) } else { try container.encodeNil(forKey: .caption) }
            try container.encode(seed, forKey: .seed)
            if let refWav { try container.encode(refWav, forKey: .refWav) } else { try container.encodeNil(forKey: .refWav) }
            try container.encode(numSteps, forKey: .numSteps)
            try container.encode(durationScale, forKey: .durationScale)
        }
    }

    /// 1行 = JSON オブジェクト1つ。改行を含む値が来ても JSON エンコードで必ずエスケープされるので、途中で改行しない
    static func encodeLine<T: Encodable>(_ command: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(command)
        guard let line = String(data: data, encoding: .utf8) else {
            throw WorkerError.protocolViolation("コマンドを JSON にできませんでした")
        }
        return line
    }
}

// MARK: - エラー

public enum WorkerError: LocalizedError, Equatable {
    case launchFailed(reason: String, stderrTail: String)
    case notRunning(stderrTail: String)
    case crashed(status: Int32, stderrTail: String)
    case workerReported(String)
    case protocolViolation(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let reason, let tail):
            return "Python ワーカーを起動できませんでした: \(reason)" + Self.tailSuffix(tail)
        case .notRunning(let tail):
            return "Python ワーカーと話せませんでした（起動していないか、落ちています）" + Self.tailSuffix(tail)
        case .crashed(let status, let tail):
            return "Python ワーカーが終了コード \(status) で落ちました" + Self.tailSuffix(tail)
        case .workerReported(let message):
            return message
        case .protocolViolation(let detail):
            return "Python ワーカーから想定外の応答が届きました: \(detail)"
        }
    }

    private static func tailSuffix(_ tail: String) -> String {
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\n---\n\(trimmed.suffix(800))"
    }
}
