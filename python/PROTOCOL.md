# Swift ⇄ Python ワーカーのやりとり

Phase 2 の音声合成は、Python のワーカーを**常駐プロセス**として起動し、標準入出力で JSON を1行ずつやり取りして行う。
モデルの読み込みは初回 約40秒・2回目以降 約5秒かかるので、プロセスは開いたままにしてモデルを載せっぱなしにする。
MPS は同時に複数の生成を走らせられないので、**生成は1本ずつ**（呼ぶ側＝Swift が順番に投げる）。

- 起動: `<repo>/.venv/bin/python <worker.py>`（既定のリポジトリは `~/dev/github/Irodori-TTS`、Python 3.11）
- 1行 = JSON オブジェクト1つ。行の途中で改行しない（`json.dumps(..., ensure_ascii=False)` をそのまま1行で）
- 標準出力はこのプロトコル専用。ログや進捗の文字列は必ず JSON に包む（`print` を素で使わない。ライブラリが stdout に書く場合は stderr へ逃がす）
- 標準エラーは人間用のログ。Swift は読み捨ててよいが、失敗時の表示に使えるよう末尾を覚えておく
- Swift が標準入力を閉じたら、ワーカーは片付けて終了する

## Swift → Python（1行ずつ）

| cmd | 形 | 意味 |
|---|---|---|
| `load` | `{"id":1,"cmd":"load","checkpoint":"Aratako/Irodori-TTS-v4.1-Small"}` | モデルを読み込む（初回は捨て焼きまで済ませる）。すでに同じモデルなら即 `done` |
| `synthesize` | 下記 | 1本焼く |
| `shutdown` | `{"id":9,"cmd":"shutdown"}` | 片付けて終了 |

`synthesize` の形:

```json
{"id":2,"cmd":"synthesize","out":"/path/out.wav","text":"ねえ……😏","caption":"少しハスキーな…",
 "seed":1,"ref_wav":null,"num_steps":40,"duration_scale":1.0}
```

- `caption` が `null` ならキャプション無し（`use_caption_condition=False`）
- `ref_wav` が `null` なら参照音声なし（`no_ref=True`）。パスがあれば参照音声として使う（`use_speaker_condition=True`）
- `out` は書き出し先の絶対パス。親フォルダは Swift 側が作る

## Python → Swift（1行ずつ。すべて `id` を持つ）

| event | 形 | 意味 |
|---|---|---|
| `ready` | `{"id":0,"event":"ready","python":"3.11.6"}` | 起動直後に1回だけ |
| `log` | `{"id":2,"event":"log","message":"..."}` | 途中経過の文字列（`log_fn` の中身など） |
| `progress` | `{"id":2,"event":"progress","value":0.42}` | 0.0〜1.0。推論エンジンに進捗の通知が無いので、**経過時間からの推定**でよい（直近の実測の平均を目安に、0.95 で頭打ち） |
| `done` | `load`: `{"id":1,"event":"done","checkpoint":"...","load_sec":38.2}`<br>`synthesize`: `{"id":2,"event":"done","path":"/path/out.wav","duration":6.2,"sample_rate":48000,"gen_sec":4.6}` | 成功 |
| `error` | `{"id":2,"event":"error","message":"..."}` | 失敗。ワーカーは死なず、次の命令を待つ |

1つの `id` に対して `log`/`progress` は何回でも来てよいが、`done` か `error` はちょうど1回で終わり。
