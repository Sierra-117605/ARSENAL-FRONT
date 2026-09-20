"""ゲームで使う音を合成して WAV ファイルを作る（assets/audio/）。

著作権の問題を避けるため、素材を外から持ってこず、波形を自分で作る。
実行：python tools/make_sounds.py
数値を変えて実行し直せば、音を作り直せる。
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100  # 1 秒あたりの標本数
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"


def write_wav(name, samples):
    """-1.0〜1.0 の並びを 16bit モノラルの WAV として保存する"""
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples)
        f.writeframes(data)
    print(f"{path.name}: {len(samples) / RATE:.2f} 秒")


def envelope(i, total, attack=0.005, decay=1.0):
    """音の立ち上がりと減衰（0〜1 の倍率）"""
    t = i / RATE
    attack_samples = max(int(attack * RATE), 1)
    if i < attack_samples:
        return i / attack_samples
    rest = (total - attack_samples) or 1
    return math.exp(-decay * 6.0 * (i - attack_samples) / rest)


def noise_burst(duration, decay=1.0, low_pass=0.0):
    """ノイズの塊（爆発・発砲の芯）"""
    total = int(duration * RATE)
    out = []
    prev = 0.0
    for i in range(total):
        n = random.uniform(-1.0, 1.0)
        if low_pass > 0.0:  # 低音寄りにする（値が大きいほど鈍い音）
            n = prev + (n - prev) / (1.0 + low_pass)
            prev = n
        out.append(n * envelope(i, total, decay=decay))
    return out


def tone(duration, start_hz, end_hz, decay=1.0, shape="sine"):
    """高さが変わる音（機械的な響き）"""
    total = int(duration * RATE)
    out = []
    phase = 0.0
    for i in range(total):
        hz = start_hz + (end_hz - start_hz) * (i / total)
        phase += 2.0 * math.pi * hz / RATE
        v = math.sin(phase)
        if shape == "square":
            v = 1.0 if v >= 0 else -1.0
        out.append(v * envelope(i, total, decay=decay))
    return out


def mix(*layers):
    """複数の音を重ねる"""
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak * 0.9 for v in out]


def main():
    random.seed(20260920)  # 毎回同じ音になるように

    # 射撃：鋭いノイズ＋低い胴鳴り
    write_wav("shot.wav", mix(noise_burst(0.22, decay=2.2, low_pass=0.6),
                              tone(0.22, 320, 90, decay=2.0, shape="square")))
    # 着弾（物に当たった）：短く硬い音
    write_wav("impact.wav", mix(noise_burst(0.16, decay=3.0, low_pass=1.2),
                                tone(0.12, 700, 200, decay=3.0)))
    # 被弾（自機が撃たれた）：低く重い衝撃
    write_wav("hit.wav", mix(noise_burst(0.35, decay=1.6, low_pass=3.0),
                             tone(0.3, 160, 60, decay=1.8)))
    # 撃破：長い爆発
    write_wav("destroy.wav", mix(noise_burst(1.1, decay=1.0, low_pass=2.0),
                                 tone(0.9, 220, 40, decay=1.2, shape="square")))
    # 足音：重い機体の踏みしめ
    write_wav("step.wav", mix(noise_burst(0.28, decay=2.4, low_pass=6.0),
                              tone(0.26, 110, 45, decay=2.4)))
    # レールガンの警告：はっきり気づく二音の繰り返し（3 回）
    alarm = []
    for _ in range(3):
        alarm += tone(0.18, 880, 880, decay=0.8)
        alarm += [0.0] * int(0.05 * RATE)
        alarm += tone(0.18, 660, 660, decay=0.8)
        alarm += [0.0] * int(0.12 * RATE)
    write_wav("alarm.wav", mix(alarm))

    # レールガンの発射：低く長い衝撃＋高い唸り
    write_wav("railgun.wav", mix(noise_burst(1.6, decay=0.9, low_pass=1.5),
                                 tone(1.4, 90, 30, decay=1.0, shape="square"),
                                 tone(0.7, 1400, 300, decay=1.6)))

    # 勝利：上がっていく音
    write_wav("victory.wav", mix(tone(0.9, 440, 880, decay=0.6),
                                 tone(0.9, 660, 1320, decay=0.8)))
    # 撃破された：下がっていく音
    write_wav("defeat.wav", mix(tone(1.2, 330, 110, decay=0.6),
                                tone(1.2, 220, 70, decay=0.8)))


if __name__ == "__main__":
    main()
