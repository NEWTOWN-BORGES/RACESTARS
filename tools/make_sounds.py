"""
RACESTARS — sintetiza os sons do jogo (sem arquivos externos).
Uso:  python tools/make_sounds.py      (precisa de numpy)
Gera game/assets/audio/*.wav (mono, 22050 Hz).

Os loops (motor, vento, música) são feitos com filtragem por FFT, que é circular,
então o fim emenda perfeitamente no começo.
"""
import os, wave
import numpy as np

SR = 22050
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'game', 'assets', 'audio'))
rng = np.random.default_rng(7)

def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
    print('som', name, f'{len(x) / SR:.2f}s')

def t_axis(sec): return np.arange(int(sec * SR)) / SR

def fft_filter(x, shape):
    """Filtra pelo espectro: shape(freqs) -> ganho. Circular (bom para loops)."""
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * shape(f), n=len(x))

def band(lo, hi, soft=1.5):
    return lambda f: 1 / (1 + (lo / np.maximum(f, 1)) ** (2 * soft)) / (1 + (f / hi) ** (2 * soft))

def env(n, a, d, sus=0.0, rel=None):
    e = np.ones(n); A = max(1, int(a * SR)); e[:A] = np.linspace(0, 1, A)
    if rel is None:
        tail = np.arange(n - A) / SR; e[A:] = sus + (1 - sus) * np.exp(-tail / max(d, 1e-3))
    return e

# ---------------------------------------------------------------- motor (loop 2 s)
def engine():
    t = t_axis(2.0); f0 = 70.0
    x = sum((1 / k ** 1.25) * np.sin(2 * np.pi * f0 * k * t + k * 0.7) for k in range(1, 10))
    x *= 1 + 0.18 * np.sin(2 * np.pi * 7 * t)
    whine = 0.12 * np.sin(2 * np.pi * 880 * t) + 0.06 * np.sin(2 * np.pi * 1320 * t)
    air = fft_filter(rng.standard_normal(len(t)), band(250, 1600)) * 0.25
    return x * 0.6 + whine + air / (np.std(air) + 1e-9) * 0.12

# ---------------------------------------------------------------- vento (loop 4 s)
def wind():
    t = t_axis(4.0)
    n = fft_filter(rng.standard_normal(len(t)), lambda f: band(120, 2500, 1.0)(f) / np.sqrt(np.maximum(f, 20) / 300))
    n /= np.std(n)
    gust = 0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t) + 0.1 * np.sin(2 * np.pi * 1.25 * t + 1)
    return n * gust

# ---------------------------------------------------------------- passagem rente
def whoosh():
    t = t_axis(0.75); n = len(t)
    noise = rng.standard_normal(n)
    lo = fft_filter(noise, band(150, 900)); hi = fft_filter(noise, band(900, 5000))
    k = np.clip(t / 0.75, 0, 1)
    x = lo * (1 - k) + hi * (1 - k) ** 2 * 0.6
    e = np.exp(-((t - 0.22) / 0.13) ** 2)
    tone = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 0.75], [700, 260])) / SR) * 0.25
    return (x / np.std(x) + tone) * e

# ---------------------------------------------------------------- batida
def crash():
    t = t_axis(1.6); n = len(t)
    boom = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 0.6], [70, 32])) / SR) * np.exp(-t / 0.35)
    burst = fft_filter(rng.standard_normal(n), band(80, 2500)); burst = burst / np.std(burst) * np.exp(-t / 0.18)
    metal = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / d) for f, a, d in [(523, 0.3, 0.5), (1187, 0.2, 0.35), (1873, 0.15, 0.25), (2741, 0.1, 0.2)])
    debris = np.zeros(n)
    for _ in range(26):
        s = rng.integers(int(0.05 * SR), int(1.2 * SR)); L = int(rng.uniform(0.01, 0.04) * SR)
        if s + L < n: debris[s:s + L] += rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.1, 0.4)
    return boom * 1.0 + burst * 0.5 + metal * 0.5 + fft_filter(debris, band(800, 6000)) * 1.2

# ---------------------------------------------------------------- largada
def start():
    t = t_axis(1.1); x = np.zeros(len(t))
    for i, f in enumerate([440.0, 554.37, 659.25, 880.0]):
        s = int(i * 0.11 * SR); tt = t[: len(t) - s]
        x[s:] += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt)) * np.exp(-tt / 0.35)
    return x

# ---------------------------------------------------------------- música (loop 8 compassos, 100 bpm)
def note(n):  # MIDI -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)

def music():
    bpm = 100; beat = 60 / bpm; bars = 8; N = int(round(bars * 4 * beat * SR))
    t = np.arange(N) / SR; out_pad = np.zeros(N); out = np.zeros(N)
    chords = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [48, 52, 55, 60]), (55, [55, 59, 62])]  # Am F C G
    bar_len = int(round(4 * beat * SR))
    def put(sig, start):
        idx = (np.arange(len(sig)) + start) % N; np.add.at(out, idx, sig)
    def put_pad(sig, start):
        idx = (np.arange(len(sig)) + start) % N; np.add.at(out_pad, idx, sig)
    for b in range(bars):
        root, tones = chords[(b // 2) % 4]
        s0 = b * bar_len
        if b % 2 == 0:  # pad dura 2 compassos
            L = 2 * bar_len; tt = np.arange(L) / SR
            e = np.minimum(1, tt / 0.8) * np.minimum(1, (tt[::-1]) / 0.6)
            pad = np.zeros(L)
            for m in tones:
                for det in (-0.12, 0.12):
                    f = note(m + 12) * 2 ** (det / 12)
                    pad += sum(np.sin(2 * np.pi * f * k * tt) / k for k in range(1, 7))
            put_pad(pad * e * 0.05, s0)
        for q in range(4):  # baixo
            if q in (0, 2):
                L = int(beat * SR); tt = np.arange(L) / SR
                f = note(root - 12)
                put((np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(4 * np.pi * f * tt)) * np.exp(-tt / 0.28) * 0.5, s0 + int(q * beat * SR))
        arp = [tones[i % len(tones)] + 24 for i in (0, 1, 2, 1, 0, 2, 1, 2)]
        for i, m in enumerate(arp):  # arpejo em colcheias
            L = int(beat * 0.5 * SR); tt = np.arange(L) / SR; f = note(m)
            tri = 2 / np.pi * np.arcsin(np.sin(2 * np.pi * f * tt))
            put(tri * np.exp(-tt / 0.12) * 0.12, s0 + int(i * beat * 0.5 * SR))
        for q in range(4):  # bateria leve
            st = s0 + int(q * beat * SR)
            if q in (0, 2):
                L = int(0.3 * SR); tt = np.arange(L) / SR
                put(np.sin(2 * np.pi * np.cumsum(np.interp(tt, [0, 0.12], [110, 42])) / SR) * np.exp(-tt / 0.12) * 0.7, st)
            else:
                L = int(0.18 * SR); nz = rng.standard_normal(L) * np.exp(-np.arange(L) / (0.05 * SR))
                put(fft_filter(nz, band(1200, 6000)) * 0.35, st)
            L = int(0.05 * SR); hat = rng.standard_normal(L) * np.exp(-np.arange(L) / (0.012 * SR))
            put(fft_filter(hat, band(6000, 10000)) * 0.12, st + int(0.5 * beat * SR))
    out_pad = fft_filter(out_pad, lambda f: 1 / (1 + (f / 1800) ** 2))
    mix = out + out_pad
    delay = int(beat * 0.75 * SR)
    mix = mix + 0.3 * np.roll(mix, delay) + 0.12 * np.roll(mix, 2 * delay)
    return mix

if __name__ == '__main__':
    save('engine_loop', engine(), 0.8)
    save('wind_loop', wind(), 0.8)
    save('whoosh', whoosh(), 0.9)
    save('crash', crash(), 0.95)
    save('start', start(), 0.7)
    save('music_loop', music(), 0.85)
