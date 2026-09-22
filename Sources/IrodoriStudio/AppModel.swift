import Foundation
import IrodoriKit
import Observation

enum SidebarItem: Hashable {
    case voiceDesign
    case references
    case project(Project.ID)
    case clips
}

enum EngineState: Equatable {
    case loading(TTSModel)
    case ready
    case failed(String)
}

/// 声づくり画面の下書き（単発で焼く用）
struct VoiceDesignDraft {
    var voice = VoiceProfile(settings: VoiceSettings(gender: .female, age: .teen, moods: [.gentle, .teasing], seed: 1))
    var text = "ねえ……さっきからずっと、こっち見てたでしょ？😏"
    var status: LineStatus = .notGenerated
    var lastClipID: GeneratedClip.ID?
}

/// アプリ全体の状態。画面は `@Environment(AppModel.self)` で受け取る。
/// 生成は必ず `enqueue` を通して1本ずつ順番に焼く（MPS は同時に1本しか走れない）。
@MainActor
@Observable
final class AppModel {
    var selection: SidebarItem? = .voiceDesign
    private(set) var engineState: EngineState
    private(set) var ttsModel: TTSModel = .small

    var design = VoiceDesignDraft()
    var references: [VoiceReference]
    var projects: [Project]
    /// 完成音声（新しい順）
    var clips: [GeneratedClip]

    private let synthesizer: any SpeechSynthesizer
    private var jobs: [JobTarget] = []
    private var runner: Task<Void, Never>?

    init(synthesizer: any SpeechSynthesizer, references: [VoiceReference], projects: [Project], clips: [GeneratedClip]) {
        self.synthesizer = synthesizer
        self.references = references
        self.projects = projects
        self.clips = clips
        self.engineState = .loading(.small)
    }

    static func makeMock() -> AppModel {
        let sample = SampleData.make(dummyAudio: AppPaths.dummyAudio)
        return AppModel(
            synthesizer: MockSpeechSynthesizer(dummyAudioDirectory: AppPaths.dummyAudio, outputDirectory: AppPaths.outputs),
            references: sample.references,
            projects: sample.projects,
            clips: sample.clips
        )
    }

    /// 本物のエンジン（Python の常駐ワーカー）に繋ぐ既定の起動方法
    static func makeLive() -> AppModel {
        let sample = SampleData.make(dummyAudio: AppPaths.dummyAudio)
        let synthesizer = PythonSpeechSynthesizer(
            pythonPath: AppPaths.enginePython,
            workerScriptPath: AppPaths.workerScript,
            outputDirectory: AppPaths.outputs,
            engineRepoPath: AppPaths.engineRepo
        )
        return AppModel(
            synthesizer: synthesizer,
            references: sample.references,
            projects: sample.projects,
            clips: sample.clips
        )
    }

    // MARK: - エンジン

    func start() async {
        await load(ttsModel)
    }

    func switchModel(_ model: TTSModel) {
        guard model != ttsModel else { return }
        ttsModel = model
        Task { await load(model) }
    }

    /// 読み込みに失敗したときに、同じモデルでもう一度試す
    func retryEngine() {
        Task { await load(ttsModel) }
    }

    private func load(_ model: TTSModel) async {
        engineState = .loading(model)
        do {
            try await synthesizer.prepare(model: model)
            if ttsModel == model { engineState = .ready }
        } catch {
            engineState = .failed(error.localizedDescription)
        }
    }

    /// 順番待ちの本数（生成中の1本は含まない）
    var queuedCount: Int { jobs.count }
    var isGenerating: Bool { runner != nil }

    // MARK: - 引く

    func reference(_ id: VoiceReference.ID?) -> VoiceReference? {
        guard let id else { return nil }
        return references.first { $0.id == id }
    }

    func clip(_ id: GeneratedClip.ID?) -> GeneratedClip? {
        guard let id else { return nil }
        return clips.first { $0.id == id }
    }

    func projectIndex(_ id: Project.ID) -> Int? {
        projects.firstIndex { $0.id == id }
    }

    // MARK: - 声づくり

    func generateDesign() {
        guard !design.status.isBusy else { return }
        enqueue(.design)
    }

    /// 見本の設定（キャプション＋seed）を声づくりに読み込む
    func applyReferenceToDesign(_ reference: VoiceReference) {
        design.voice.load(reference)
        selection = .voiceDesign
    }

    /// 今の声づくりの設定と、最後に焼いた音声を見本として保存する
    @discardableResult
    func saveDesignAsReference(name: String) -> VoiceReference {
        let clip = clip(design.lastClipID)
        let reference = VoiceReference(
            name: name,
            settings: design.voice.settings,
            caption: design.voice.caption,
            sampleText: clip?.text ?? design.text,
            audioURL: clip?.audioURL
        )
        references.insert(reference, at: 0)
        return reference
    }

    // MARK: - 声の見本

    func renameReference(_ id: VoiceReference.ID, to name: String) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].name = name
    }

    /// 見本を消す。その見本を読み込んだり固定したりしている声（声づくり・全台本のキャラ）からも外す
    func deleteReference(_ id: VoiceReference.ID) {
        references.removeAll { $0.id == id }
        design.voice.detachReference(id)
        for p in projects.indices {
            for c in projects[p].characters.indices {
                projects[p].characters[c].voice.detachReference(id)
            }
        }
    }

    // MARK: - 台本

    @discardableResult
    func addProject(name: String = "新しい台本") -> Project {
        let project = Project(name: name)
        projects.append(project)
        selection = .project(project.id)
        return project
    }

    func deleteProject(_ id: Project.ID) {
        jobs.removeAll { $0.projectID == id }
        projects.removeAll { $0.id == id }
        if selection == .project(id) { selection = .voiceDesign }
    }

    func generateLine(projectID: Project.ID, lineID: ScriptLine.ID) {
        guard let line = projects.first(where: { $0.id == projectID })?.lines.first(where: { $0.id == lineID }),
              !line.status.isBusy else { return }
        enqueue(.line(projectID: projectID, lineID: lineID))
    }

    /// 未生成・失敗の行をまとめて順番に焼く
    func generateAll(projectID: Project.ID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        for line in project.lines where line.status == .notGenerated || isFailed(line.status) {
            generateLine(projectID: projectID, lineID: line.id)
        }
    }

    /// 順番待ちの行を取り消す（生成中の1本はそのまま焼き切る）
    func cancelQueued(projectID: Project.ID) {
        let cancelled = jobs.filter { $0.projectID == projectID }
        jobs.removeAll { $0.projectID == projectID }
        for target in cancelled { setStatus(.notGenerated, for: target) }
    }

    /// 行を消す前に呼ぶ。順番待ちなら取り消す（生成中なら、焼き上がっても捨てる）
    func cancelLine(projectID: Project.ID, lineID: ScriptLine.ID) {
        jobs.removeAll { $0 == .line(projectID: projectID, lineID: lineID) }
    }

    // MARK: - 生成キュー

    /// 今の内容から、焼く指示と完成音声に残す情報を組み立てる。対象が消えていれば nil。
    /// 順番が来たときに組み立てるので、待機中に書き換えた内容もそのまま反映される。
    private func resolve(_ target: JobTarget) -> Job? {
        switch target {
        case .design:
            let voice = design.voice
            return Job(
                target: target,
                request: makeRequest(text: design.text, voice: voice),
                characterName: nil,
                referenceName: reference(voice.fixedReferenceID)?.name,
                source: .voiceDesign
            )
        case .line(let projectID, let lineID):
            guard let project = projects.first(where: { $0.id == projectID }),
                  let line = project.lines.first(where: { $0.id == lineID }) else { return nil }
            let character = project.character(line.characterID)
            let voice = character?.voice ?? VoiceProfile()
            var request = makeRequest(text: line.text, voice: voice)
            if let caption = line.captionOverride { request.caption = caption.isEmpty ? nil : caption }
            if let seed = line.seedOverride { request.seed = seed }
            return Job(
                target: target,
                request: request,
                characterName: character?.name,
                referenceName: reference(voice.fixedReferenceID)?.name,
                source: .project(id: projectID, name: project.name)
            )
        }
    }

    private func makeRequest(text: String, voice: VoiceProfile) -> SynthesisRequest {
        SynthesisRequest(
            text: text,
            caption: voice.caption.isEmpty ? nil : voice.caption,
            seed: voice.settings.seed,
            referenceAudioURL: reference(voice.fixedReferenceID)?.audioURL
        )
    }

    private func enqueue(_ target: JobTarget) {
        jobs.append(target)
        setStatus(.queued, for: target)
        guard runner == nil else { return }
        runner = Task { await drain() }
    }

    private func drain() async {
        while !jobs.isEmpty {
            while engineState != .ready {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !jobs.isEmpty else { break }
            let target = jobs.removeFirst()
            guard let job = resolve(target) else { continue }
            setStatus(.generating(progress: 0), for: target)
            do {
                let result = try await synthesizer.synthesize(job.request) { [weak self] value in
                    Task { @MainActor in self?.updateProgress(value, for: target) }
                }
                finish(job, result: result)
            } catch {
                setStatus(.failed(message: error.localizedDescription), for: target)
            }
        }
        runner = nil
    }

    private func updateProgress(_ value: Double, for target: JobTarget) {
        // 焼き終わった後に届いた進捗で「生成中」に戻さない
        guard case .generating = status(of: target) else { return }
        setStatus(.generating(progress: value), for: target)
    }

    private func finish(_ job: Job, result: SynthesisResult) {
        // 焼いている間に行が消されたら、音声は捨てる
        guard let current = resolve(job.target) else { return }
        let clip = GeneratedClip(
            text: job.request.text,
            caption: job.request.caption,
            seed: job.request.seed,
            referenceName: job.referenceName,
            characterName: job.characterName,
            audioURL: result.audioURL,
            duration: result.duration,
            source: job.source
        )
        clips.insert(clip, at: 0)
        // 焼いている間に書き換えられていたら、音声は残しつつ「未生成」に戻して再生成を促す
        let status: LineStatus = current.request == job.request ? .generated : .notGenerated
        switch job.target {
        case .design:
            design.lastClipID = clip.id
            design.status = status
        case .line(let projectID, let lineID):
            mutateLine(projectID: projectID, lineID: lineID) {
                $0.clipID = clip.id
                $0.status = status
            }
        }
    }

    private func status(of target: JobTarget) -> LineStatus? {
        switch target {
        case .design:
            return design.status
        case .line(let projectID, let lineID):
            return projects.first { $0.id == projectID }?.lines.first { $0.id == lineID }?.status
        }
    }

    private func setStatus(_ status: LineStatus, for target: JobTarget) {
        switch target {
        case .design:
            design.status = status
        case .line(let projectID, let lineID):
            mutateLine(projectID: projectID, lineID: lineID) { $0.status = status }
        }
    }

    private func mutateLine(projectID: Project.ID, lineID: ScriptLine.ID, _ body: (inout ScriptLine) -> Void) {
        guard let p = projectIndex(projectID),
              let l = projects[p].lines.firstIndex(where: { $0.id == lineID }) else { return }
        body(&projects[p].lines[l])
    }

    private func isFailed(_ status: LineStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    /// キューに積むのは「何を焼くか」だけ
    private enum JobTarget: Equatable {
        case design
        case line(projectID: Project.ID, lineID: ScriptLine.ID)

        var projectID: Project.ID? {
            if case .line(let projectID, _) = self { return projectID }
            return nil
        }
    }

    /// 順番が来たときに組み立てた、焼く指示と完成音声に残す情報
    private struct Job {
        let target: JobTarget
        let request: SynthesisRequest
        let characterName: String?
        let referenceName: String?
        let source: GeneratedClip.Source
    }
}
