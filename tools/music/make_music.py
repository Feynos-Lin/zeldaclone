"""Renders Wrenmoor's eerie forest theme to assets/music/forest.ogg.

Usage: python3 make_music.py <out.wav>   (then: ffmpeg -i out.wav -c:a libvorbis -q:a 3 forest.ogg)

A slow D-minor piece built for looping: a breathing pad on a Dm - Bbmaj7 - Gm9 -
Asus4/A cycle, a sparse music-box melody drowned in reverb, a hollow wooden flute
that wanders in now and then, wind in the trees, a far-off owl, and a low heartbeat
drum on the last bars. The tail is wrapped back onto the start so the loop is seamless.
"""
import sys
import numpy as np
from scipy.signal import lfilter, butter, sosfilt

SR = 32000
BPM = 56.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 24
LEN = BARS * BAR
N = int(LEN * SR)
TAIL = int(8.0 * SR)
rng = np.random.default_rng(13)
t_all = np.arange(N + TAIL) / SR


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def env_adsr(n, a, d, s, r, sr=SR):
    e = np.ones(n) * s
    ai, di, ri = int(a * sr), int(d * sr), int(r * sr)
    ai = min(ai, n); e[:ai] = np.linspace(0, 1, ai, endpoint=False)
    d_end = min(ai + di, n); e[ai:d_end] = np.linspace(1, s, d_end - ai, endpoint=False)
    if ri > 0:
        e[-ri:] *= np.linspace(1, 0, ri)
    return e


def add(buf, start_s, sig):
    i = int(start_s * SR)
    j = min(i + len(sig), len(buf))
    buf[i:j] += sig[:j - i]


def lowpass(x, fc, order=2):
    return sosfilt(butter(order, fc / (SR / 2), output='sos'), x)


def highpass(x, fc, order=2):
    return sosfilt(butter(order, fc / (SR / 2), btype='high', output='sos'), x)


def reverb(x, mix=0.35, size=1.0):
    # Schroeder: parallel combs into series allpasses
    out = np.zeros_like(x)
    for d, g in [(1557, 0.84), (1617, 0.83), (1491, 0.85), (1422, 0.84), (1277, 0.83), (1356, 0.84)]:
        d = int(d * size * SR / 25000)
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out += lfilter([1.0], a, x)
    out /= 6
    for d, g in [(225, 0.5), (556, 0.5), (441, 0.5)]:
        d = int(d * SR / 25000)
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out = lfilter(b, a, out)
    return x * (1 - mix) + lowpass(out, 5000) * mix


# ------------------------------------------------------------------ pad
CHORDS = [  # (notes, bars)
    ([50, 57, 62, 65, 69], 2),        # Dm
    ([46, 53, 57, 62, 65], 2),        # Bbmaj7
    ([43, 50, 58, 62, 69], 2),        # Gm9
    ([45, 52, 57, 62, 64], 1),        # Asus4
    ([45, 52, 57, 61, 64], 1),        # A
]
pad = np.zeros(N + TAIL)
bar = 0
while bar < BARS:
    for notes, nb in CHORDS:
        if bar >= BARS:
            break
        dur = nb * BAR + 2.5
        n = int(dur * SR)
        tt = np.arange(n) / SR
        sig = np.zeros(n)
        for k, m in enumerate(notes):
            f = midi(m)
            for det in (-0.12, 0.0, 0.11):
                ph = rng.uniform(0, 1)
                ff = f * 2 ** (det / 12)
                saw = 2 * ((tt * ff + ph) % 1.0) - 1
                sig += saw * (0.5 if k == 0 else 0.32)
        sig = lowpass(sig, 900 + 300 * np.sin(bar * 0.7))
        sig *= env_adsr(n, 1.6, 0.5, 0.85, 2.2)
        sig *= 1 + 0.15 * np.sin(2 * np.pi * 0.21 * tt)          # slow breathing
        add(pad, bar * BAR, sig * 0.05)
        bar += nb

# ------------------------------------------------------------------ music box melody (sparse, in D minor with a raised 6th)
def bell(f, dur=3.2):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    s = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * f * 2.76 * tt) * np.exp(-tt * 3)
         + 0.2 * np.sin(2 * np.pi * f * 5.4 * tt) * np.exp(-tt * 6))
    return s * np.exp(-tt * 1.4) * np.minimum(1, tt * 400)

MEL = [  # (beat, midi) across 24 bars = 96 beats; rests are the point
    (0, 74), (1.5, 77), (3, 76), (6, 69),
    (8, 74), (9, 72), (10.5, 70), (14, 69),
    (16, 67), (17.5, 70), (19, 74), (22, 73),
    (26, 76), (27, 77), (28.5, 79), (31, 76),
    (34, 74), (36, 81), (37, 79), (38.5, 77), (42, 76),
    (44, 73), (46, 69),
    (50, 74), (51.5, 77), (53, 76), (56, 71), (58, 69),
    (62, 70), (63, 74), (64.5, 77), (67, 76),
    (72, 74), (73, 81), (74.5, 79), (76, 77), (78, 76),
    (82, 73), (84, 74), (86, 69), (90, 74),
]
box = np.zeros(N + TAIL)
for b, m in MEL:
    add(box, b * BEAT + rng.uniform(-0.02, 0.02), bell(midi(m)) * rng.uniform(0.75, 1.0))
box = highpass(box, 300)

# ------------------------------------------------------------------ hollow flute (breathy sine with slow vibrato), two phrases
def flute(notes):
    out = []
    for m, d in notes:
        n = int(d * BEAT * SR)
        tt = np.arange(n) / SR
        f = midi(m) * (1 + 0.006 * np.sin(2 * np.pi * 5.0 * tt) * np.minimum(1, tt * 1.5))
        ph = np.cumsum(2 * np.pi * f / SR)
        breath = lowpass(rng.normal(0, 1, n), 2500) * 0.12
        s = (np.sin(ph) + 0.15 * np.sin(2 * ph) + breath) * env_adsr(n, 0.25, 0.2, 0.8, 0.4)
        out.append(s)
    return np.concatenate(out)

fl = np.zeros(N + TAIL)
add(fl, 32 * BEAT, flute([(62, 3), (65, 1), (64, 2), (60, 2), (62, 6)]))
add(fl, 64 * BEAT, flute([(69, 2), (67, 1), (65, 1), (64, 3), (61, 1), (62, 6)]))
fl = lowpass(fl, 3000)

# ------------------------------------------------------------------ wind
wind = rng.normal(0, 1, N + TAIL)
sweep = 0.5 + 0.5 * np.sin(2 * np.pi * t_all / (LEN / 3)) * np.sin(2 * np.pi * t_all / 7.3)
wind_lo = lowpass(wind, 500)
wind_hi = highpass(lowpass(wind, 2200), 900)
wind = wind_lo * 0.5 + wind_hi * (0.15 + 0.35 * sweep)
wind *= 0.06 * (0.6 + 0.4 * sweep)

# ------------------------------------------------------------------ owl, far away
def hoot(f=380.0):
    n = int(0.5 * SR); tt = np.arange(n) / SR
    ff = f * (1 - 0.06 * tt)
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.sin(np.pi * tt / 0.5) ** 2
owl = np.zeros(N + TAIL)
for start in (11.0, 52.5, 81.0):
    add(owl, start, hoot()); add(owl, start + 0.6, hoot(360)); add(owl, start + 1.5, hoot(370) * 0.7)
owl = lowpass(owl, 1200) * 0.06

# ------------------------------------------------------------------ heartbeat drum, last six bars
drum = np.zeros(N + TAIL)
def thump():
    n = int(0.5 * SR); tt = np.arange(n) / SR
    return np.sin(2 * np.pi * (48 + 40 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 9)
for b in range(18 * 4, 24 * 4, 2):
    add(drum, b * BEAT, thump() * 0.5)
    add(drum, b * BEAT + 0.32, thump() * 0.32)
drum = lowpass(drum, 300)

mix = pad + box * 0.11 + fl * 0.05 + owl
mix = reverb(mix, mix=0.45, size=1.3)
mix += wind + drum * 0.5
# wrap the tail onto the start so the loop is seamless
loop = mix[:N].copy()
loop[:TAIL] += mix[N:N + TAIL]
loop /= np.max(np.abs(loop)) * 1.12
from scipy.io import wavfile
wavfile.write(sys.argv[1], SR, (loop * 32767).astype(np.int16))
print('rendered %.1f s' % LEN)
