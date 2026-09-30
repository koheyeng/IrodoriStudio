#!/usr/bin/env python3
"""Irodori Studio の音声合成ワーカー。

Swift側と標準入出力でJSONプロトコル(PROTOCOL.md)をやり取りする常駐プロセス。
モデルを一度読み込んだら載せっぱなしにし、synthesizeが来るたびに1本ずつ焼く。
"""
from __future__ import annotations

import gc
import json
import os
import platform
import sys
import threading
import time
from collections import deque
from pathlib import Path

# --- 最重要: 推論ライブラリ(PyTorch/MPSやhuggingface_hubの進捗バーなど)が
# stdoutに直接書き込むとJSONプロトコルが壊れる。Pythonレベルのsys.stdoutだけでなく
# OSのファイルディスクリプタ1番(stdout)そのものをstderrへ付け替え、
# 本物のstdout(プロトコル送信用)は複製したfdとして別に確保しておく。
_REAL_STDOUT_FD = os.dup(1)
os.dup2(2, 1)
_REAL_STDOUT = os.fdopen(_REAL_STDOUT_FD, "w", encoding="utf-8")
_EMIT_LOCK = threading.Lock()


def _emit(obj: dict) -> None:
    """JSONを1行、本物のstdoutへ書く。複数スレッドから呼ばれるのでロックする。"""
    line = json.dumps(obj, ensure_ascii=False)
    with _EMIT_LOCK:
        _REAL_STDOUT.write(line + "\n")
        _REAL_STDOUT.flush()


# Irodori-TTSリポジトリをsys.pathへ追加(環境変数IRODORI_TTS_REPO、未設定なら既定パス)
_REPO = Path(os.environ.get("IRODORI_TTS_REPO", "~/dev/github/Irodori-TTS")).expanduser()
sys.path.insert(0, str(_REPO))

import librosa  # noqa: E402
import torch  # noqa: E402

from irodori_tts.inference_runtime import (  # noqa: E402
    InferenceRuntime,
    RuntimeKey,
    SamplingRequest,
    download_hf_checkpoint,
    resolve_cfg_scales,
    save_wav,
)

_DEFAULT_ESTIMATE_SEC = 5.0  # 初回(実測なし)の見込み生成時間
_MOVING_AVG_WINDOW = 5  # 見込み時間に使う直近の実測本数


class Worker:
    def __init__(self) -> None:
        self.runtime: InferenceRuntime | None = None
        self.checkpoint: str | None = None
        self.gen_times: deque[float] = deque(maxlen=_MOVING_AVG_WINDOW)

    def _estimate_sec(self, text: str) -> float:
        if self.gen_times:
            return sum(self.gen_times) / len(self.gen_times)
        # 実測がまだ無いのでデフォルト値をセリフの長さで軽くスケールする
        scale = max(0.5, min(2.0, len(text) / 40))
        return _DEFAULT_ESTIMATE_SEC * scale

    def handle_load(self, msg: dict) -> None:
        req_id = msg["id"]
        checkpoint = msg["checkpoint"]
        if self.runtime is not None and self.checkpoint == checkpoint:
            _emit({"id": req_id, "event": "done", "checkpoint": checkpoint, "load_sec": 0.0})
            return

        # 前のモデルを先に捨てる。新旧が同時に載ると Small(約7.5GB)+Large(約19GB) でメモリが溢れる
        if self.runtime is not None:
            self.runtime = None
            self.checkpoint = None
            gc.collect()
            torch.mps.empty_cache()
        self.gen_times.clear()  # 進捗の見込み時間はモデルごとに測り直す

        t0 = time.perf_counter()
        ckpt_path = download_hf_checkpoint(checkpoint)
        rt = InferenceRuntime.from_key(RuntimeKey(
            checkpoint=ckpt_path,
            model_device="mps",
            codec_repo="Aratako/Semantic-DACVAE-Japanese-32dim",
            model_precision="fp32",
            codec_device="mps",
            codec_precision="fp32",
            codec_deterministic_encode=True,
            codec_deterministic_decode=True,
            compile_model=False,
            compile_dynamic=False,
        ))
        rt.synthesize(SamplingRequest(text="テストです。", no_ref=True, seed=0), log_fn=None)  # 捨て焼き
        self.runtime = rt
        self.checkpoint = checkpoint
        load_sec = time.perf_counter() - t0
        _emit({"id": req_id, "event": "done", "checkpoint": checkpoint, "load_sec": round(load_sec, 2)})

    def handle_synthesize(self, msg: dict) -> None:
        req_id = msg["id"]
        if self.runtime is None:
            raise RuntimeError("モデルが読み込まれていません。先にloadしてください。")

        text = msg["text"]
        caption = msg.get("caption")
        ref_wav = msg.get("ref_wav")
        out_path = msg["out"]

        use_caption_condition = caption is not None
        use_speaker_condition = ref_wav is not None

        cfg_text, cfg_caption, cfg_speaker, _ = resolve_cfg_scales(
            cfg_guidance_mode="independent",
            cfg_scale_text=3.0,
            cfg_scale_caption=3.0,
            cfg_scale_speaker=5.0,
            cfg_scale=None,
            use_caption_condition=use_caption_condition,
            use_speaker_condition=use_speaker_condition,
        )
        req = SamplingRequest(
            text=text,
            caption=caption if use_caption_condition else None,
            ref_wav=ref_wav,
            no_ref=not use_speaker_condition,
            seed=msg.get("seed"),
            num_steps=msg.get("num_steps"),
            duration_scale=msg.get("duration_scale", 1.0),
            cfg_scale_text=cfg_text,
            cfg_scale_caption=cfg_caption,
            cfg_scale_speaker=cfg_speaker,
        )

        def _log(message: str) -> None:
            _emit({"id": req_id, "event": "log", "message": message})

        # 推論エンジンに進捗通知が無いので、別スレッドで焼きつつ
        # メインスレッドが0.2秒おきに「経過時間 / 見込み時間」をprogressとして送る。
        result: dict = {}
        done_flag = threading.Event()

        def _run() -> None:
            t0 = time.perf_counter()
            try:
                result["res"] = self.runtime.synthesize(req, log_fn=_log)
            except Exception as exc:  # noqa: BLE001 - ワーカーを落とさずerrorイベントに変換する
                result["error"] = exc
            finally:
                result["elapsed"] = time.perf_counter() - t0
                done_flag.set()

        est_sec = self._estimate_sec(text)
        thread = threading.Thread(target=_run, daemon=True)
        t_start = time.perf_counter()
        thread.start()
        while not done_flag.is_set():
            value = min(0.95, (time.perf_counter() - t_start) / est_sec)
            _emit({"id": req_id, "event": "progress", "value": round(value, 3)})
            done_flag.wait(0.2)
        thread.join()

        if "error" in result:
            raise result["error"]

        res = result["res"]
        gen_sec = result["elapsed"]

        # 頭と尻の無音を詰めてから保存する（句読点だけのセリフだと前後に1秒ほど無音が入ることがある）
        audio, sr = res.audio.reshape(-1), res.sample_rate
        iv = librosa.effects.split(audio.float().cpu().numpy(), top_db=40)
        if len(iv) > 0:
            start = max(0, iv[0][0] - int(0.08 * sr))
            end = min(audio.shape[-1], iv[-1][1] + int(0.25 * sr))
            audio = audio[start:end]
        save_wav(out_path, audio.unsqueeze(0), sr)

        self.gen_times.append(gen_sec)
        duration = audio.shape[-1] / sr
        _emit({
            "id": req_id,
            "event": "done",
            "path": out_path,
            "duration": round(duration, 3),
            "sample_rate": sr,
            "gen_sec": round(gen_sec, 3),
        })

    def handle(self, msg: dict) -> bool:
        """1コマンドを処理する。Trueを返したらワーカーを終了する。"""
        cmd = msg.get("cmd")
        if cmd == "shutdown":
            return True
        if cmd == "load":
            self.handle_load(msg)
        elif cmd == "synthesize":
            self.handle_synthesize(msg)
        else:
            raise ValueError(f"未知のcmd: {cmd!r}")
        return False


def main() -> None:
    _emit({"id": 0, "event": "ready", "python": platform.python_version()})
    worker = Worker()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as exc:
            _emit({"id": None, "event": "error", "message": f"JSON解析エラー: {exc}"})
            continue

        req_id = msg.get("id")
        try:
            if worker.handle(msg):
                break
        except Exception as exc:  # noqa: BLE001 - どんな例外でもプロセスは落とさずerrorを返す
            _emit({"id": req_id, "event": "error", "message": f"{type(exc).__name__}: {exc}"})
    # 標準入力のEOF、またはshutdownコマンドで静かに終了する


if __name__ == "__main__":
    main()
