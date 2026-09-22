import Foundation
import Testing
@testable import IrodoriKit

/// Python プロセスを実際には起動せずに確かめられる部分だけをテストする
/// （1行 JSON の組み立て、分割された行の組み立て、想定外の行の無視）

@Suite struct LineBufferTests {
    @Test func feedsOneCompleteLine() {
        var buffer = LineBuffer()
        let lines = buffer.feed(Data("{\"a\":1}\n".utf8))
        #expect(lines == ["{\"a\":1}"])
    }

    @Test func feedsMultipleLinesInOneChunk() {
        var buffer = LineBuffer()
        let lines = buffer.feed(Data("line1\nline2\nline3\n".utf8))
        #expect(lines == ["line1", "line2", "line3"])
    }

    @Test func reassemblesLineSplitAcrossChunks() {
        var buffer = LineBuffer()
        let first = buffer.feed(Data("{\"id\":1,\"eve".utf8))
        #expect(first.isEmpty)
        let second = buffer.feed(Data("nt\":\"ready\"}\n".utf8))
        #expect(second == ["{\"id\":1,\"event\":\"ready\"}"])
    }

    @Test func keepsTrailingPartialLineUntilNewlineArrives() {
        var buffer = LineBuffer()
        let lines = buffer.feed(Data("complete\npartial".utf8))
        #expect(lines == ["complete"])
        let rest = buffer.feed(Data("-line\n".utf8))
        #expect(rest == ["partial-line"])
    }

    @Test func handlesJapaneseTextSplitMidCharacter() {
        // マルチバイト文字の境目でチャンクが割れても文字化けしないこと
        let full = Data("{\"event\":\"log\",\"id\":1,\"message\":\"読み込み中…\"}\n".utf8)
        var buffer = LineBuffer()
        let mid = full.count / 2
        var lines = buffer.feed(full.subdata(in: full.startIndex..<full.index(full.startIndex, offsetBy: mid)))
        #expect(lines.isEmpty)
        lines = buffer.feed(full.subdata(in: full.index(full.startIndex, offsetBy: mid)..<full.endIndex))
        #expect(lines == ["{\"event\":\"log\",\"id\":1,\"message\":\"読み込み中…\"}"])
    }
}

@Suite struct EncodeLineTests {
    private func decode(_ line: String) -> [String: Any] {
        let data = Data(line.utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    @Test func loadCommandHasExpectedFields() throws {
        let line = try PythonSpeechSynthesizer.encodeLine(
            PythonSpeechSynthesizer.LoadCommand(id: 1, checkpoint: "Aratako/Irodori-TTS-v4.1-Small")
        )
        #expect(!line.contains("\n"))
        let obj = decode(line)
        #expect(obj["id"] as? Int == 1)
        #expect(obj["cmd"] as? String == "load")
        #expect(obj["checkpoint"] as? String == "Aratako/Irodori-TTS-v4.1-Small")
    }

    @Test func synthesizeCommandOmitsNothingAndUsesExplicitNullForMissingOptionals() throws {
        let line = try PythonSpeechSynthesizer.encodeLine(
            PythonSpeechSynthesizer.SynthesizeCommand(
                id: 2, out: "/tmp/out.wav", text: "ねえ……😏", caption: nil, seed: 1,
                refWav: nil, numSteps: 40, durationScale: 1.0
            )
        )
        #expect(!line.contains("\n"))
        let obj = decode(line)
        #expect(obj["id"] as? Int == 2)
        #expect(obj["cmd"] as? String == "synthesize")
        #expect(obj["out"] as? String == "/tmp/out.wav")
        #expect(obj["text"] as? String == "ねえ……😏")
        #expect(obj["seed"] as? Int == 1)
        #expect(obj["num_steps"] as? Int == 40)
        #expect(obj["duration_scale"] as? Double == 1.0)
        // キーが省略されるのではなく、明示的に null で入っていること
        #expect(obj.keys.contains("caption"))
        #expect(obj["caption"] is NSNull)
        #expect(obj.keys.contains("ref_wav"))
        #expect(obj["ref_wav"] is NSNull)
    }

    @Test func synthesizeCommandCarriesPresentOptionals() throws {
        let line = try PythonSpeechSynthesizer.encodeLine(
            PythonSpeechSynthesizer.SynthesizeCommand(
                id: 3, out: "/tmp/out.wav", text: "テスト", caption: "少しハスキーな声。", seed: 5,
                refWav: "/tmp/ref.wav", numSteps: 40, durationScale: 1.2
            )
        )
        let obj = decode(line)
        #expect(obj["caption"] as? String == "少しハスキーな声。")
        #expect(obj["ref_wav"] as? String == "/tmp/ref.wav")
        #expect(obj["duration_scale"] as? Double == 1.2)
    }
}

@Suite struct ParseEventTests {
    @Test func parsesReady() {
        #expect(PythonSpeechSynthesizer.parseEvent(#"{"id":0,"event":"ready","python":"3.11.6"}"#) == .ready)
    }

    @Test func parsesLog() {
        #expect(
            PythonSpeechSynthesizer.parseEvent(#"{"id":2,"event":"log","message":"読み込み中"}"#)
                == .log(id: 2, message: "読み込み中")
        )
    }

    @Test func parsesProgress() {
        #expect(
            PythonSpeechSynthesizer.parseEvent(#"{"id":2,"event":"progress","value":0.42}"#)
                == .progress(id: 2, value: 0.42)
        )
    }

    @Test func parsesSynthesizeDoneWithPathAndDuration() {
        let line = #"{"id":2,"event":"done","path":"/tmp/out.wav","duration":6.2,"sample_rate":48000,"gen_sec":4.6}"#
        #expect(PythonSpeechSynthesizer.parseEvent(line) == .done(id: 2, path: "/tmp/out.wav", duration: 6.2))
    }

    @Test func parsesLoadDoneWithoutPathOrDuration() {
        let line = #"{"id":1,"event":"done","checkpoint":"Aratako/Irodori-TTS-v4.1-Small","load_sec":38.2}"#
        #expect(PythonSpeechSynthesizer.parseEvent(line) == .done(id: 1, path: nil, duration: nil))
    }

    @Test func parsesError() {
        #expect(
            PythonSpeechSynthesizer.parseEvent(#"{"id":2,"event":"error","message":"CUDA out of memory"}"#)
                == .error(id: 2, message: "CUDA out of memory")
        )
    }

    @Test func ignoresInvalidJSON() {
        #expect(PythonSpeechSynthesizer.parseEvent("not json at all") == nil)
    }

    @Test func ignoresLineMissingEvent() {
        #expect(PythonSpeechSynthesizer.parseEvent(#"{"id":1,"python":"3.11.6"}"#) == nil)
    }

    @Test func ignoresUnknownEventType() {
        #expect(PythonSpeechSynthesizer.parseEvent(#"{"id":1,"event":"mystery"}"#) == nil)
    }

    @Test func ignoresLogMissingMessage() {
        #expect(PythonSpeechSynthesizer.parseEvent(#"{"id":1,"event":"log"}"#) == nil)
    }

    @Test func ignoresProgressMissingId() {
        #expect(PythonSpeechSynthesizer.parseEvent(#"{"event":"progress","value":0.5}"#) == nil)
    }
}
