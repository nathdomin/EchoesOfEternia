# Gera os efeitos sonoros do jogo (sintese retro, 8-bit). Saida: audio/sfx/*.wav
import numpy as np, wave, sys, os
SR = 22050
rng = np.random.default_rng(7)
out = sys.argv[1]
os.makedirs(out, exist_ok=True)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=None, curve=2.0):
    x = np.linspace(0, 1, n)
    e = (1 - x) ** curve
    na = max(1, int(SR * a)); e[:na] *= np.linspace(0, 1, na)
    return e
def sweep(f0, f1, d, kind="square", duty=0.5):
    f = np.geomspace(f0, f1, int(SR * d)); ph = np.cumsum(f) / SR
    if kind == "square": return np.where((ph % 1) < duty, 1.0, -1.0)
    if kind == "tri": return 2 * np.abs(2 * (ph % 1) - 1) - 1
    if kind == "saw": return 2 * (ph % 1) - 1
    return np.sin(2 * np.pi * ph)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def lowpass(x, a):
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x): acc += a * (v - acc); y[i] = acc
    return y
def lp_sweep(x, a0, a1):
    y = np.zeros_like(x); acc = 0.0; aa = np.linspace(a0, a1, len(x))
    for i, v in enumerate(x): acc += aa[i] * (v - acc); y[i] = acc
    return y
def note(f, d, kind="square", duty=0.5, curve=1.5):
    s = sweep(f, f, d, kind, duty); return s * env(len(s), curve=curve)
def cat(*xs): return np.concatenate(xs)
def mix(*xs):
    n = max(len(x) for x in xs); y = np.zeros(n)
    for x in xs: y[:len(x)] += x
    return y
## Gate 5: todos os efeitos com o mesmo volume percebido. O ganho e
## calculado pelo RMS das partes com som (nao pelo pico) ate `target` dB;
## o pico fica abaixo de -1 dB. `vol` sobrou da versao anterior e e ignorado.
TARGETS = {"amb_wind": -30, "amb_cave": -31, "drip": -22, "bird0": -25, "bird1": -25, "bird2": -25,
		"swing": -18, "throw": -18, "hit": -16, "hurt": -16, "monster_die": -17, "death": -15,
		"levelup": -15, "quest": -16, "potion": -17, "magic": -18, "explosion": -15, "heal": -17,
		"slam": -14, "zone": -17, "warning": -17, "dodge": -19}
def save(name, x, vol=0.5):
    x = x / (np.max(np.abs(x)) + 1e-9)
    act = x[np.abs(x) > 0.02]
    rms = np.sqrt(np.mean(act ** 2)) if len(act) else 1.0
    x = x * (10 ** (TARGETS.get(name, -17) / 20.0) / rms)
    peak = np.max(np.abs(x))
    if peak > 0.89:
        x = np.tanh(x / 0.89 * 1.2) / np.tanh(1.2) * 0.89  # limita sem estalar
    fade = min(len(x), int(SR * 0.004)); x[-fade:] *= np.linspace(1, 0, fade)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

N = lambda d: noise(d)
save("swing", lp_sweep(N(0.14), 0.05, 0.35) * env(int(SR*0.14), a=0.03, curve=2), 0.35)
save("throw", lp_sweep(N(0.12), 0.3, 0.08) * env(int(SR*0.12), a=0.01, curve=2) + 0.3*sweep(1400, 700, 0.12, "sine")*env(int(SR*0.12)), 0.32)
save("hit", mix(lowpass(N(0.1), 0.35) * env(int(SR*0.1), curve=3), 0.9*sweep(180, 60, 0.1, "sine")*env(int(SR*0.1), curve=2)), 0.5)
save("hurt", mix(sweep(520, 160, 0.18, "square", 0.3)*env(int(SR*0.18), curve=1.2)*0.6, lowpass(N(0.08), 0.5)*env(int(SR*0.08))*0.5), 0.42)
save("monster_die", mix(sweep(700, 90, 0.32, "square", 0.25)*env(int(SR*0.32), curve=1.3), lowpass(N(0.32), 0.2)*env(int(SR*0.32), curve=2)*0.6), 0.42)
save("death", cat(note(392, 0.2, curve=0.8), note(330, 0.2, curve=0.8), note(262, 0.2, curve=0.8), sweep(196, 98, 0.5, "tri")*env(int(SR*0.5), curve=1)), 0.4)
save("levelup", cat(*[note(f, 0.09, duty=0.25, curve=0.6) for f in [523, 659, 784, 1047]], note(1319, 0.35, duty=0.25, curve=1.5)), 0.38)
save("quest", cat(note(392, 0.1, duty=0.25, curve=0.5), note(523, 0.1, duty=0.25, curve=0.5), note(659, 0.1, duty=0.25, curve=0.5), mix(note(784, 0.45, duty=0.25), note(523, 0.45, "tri")*0.6)), 0.38)
d = 0.4; tt = t(d); f = 300 + 500 * tt / d + 60 * np.sin(2 * np.pi * 18 * tt)
save("potion", np.sin(2*np.pi*np.cumsum(f)/SR) * env(len(tt), a=0.02, curve=1.2), 0.4)
d = 0.38; sh = sweep(400, 1600, d, "sine") * env(int(SR*d), a=0.02, curve=1.3)
save("magic", mix(sh, 0.4*sweep(800, 3200, d, "tri")*env(int(SR*d), curve=2), 0.15*lowpass(N(d), 0.6)*env(int(SR*d))), 0.38)
save("explosion", mix(lp_sweep(N(0.6), 0.5, 0.03) * env(int(SR*0.6), a=0.002, curve=1.6), 0.8*sweep(120, 40, 0.4, "sine")*env(int(SR*0.4), curve=2)), 0.55)
save("heal", cat(*[mix(note(f, 0.12, "sine", curve=0.7), 0.3*note(f*2, 0.12, "tri", curve=1)) for f in [523, 659, 784]], note(1047, 0.3, "sine")), 0.36)
save("slam", mix(0.9*sweep(90, 30, 0.55, "sine")*env(int(SR*0.55), a=0.002, curve=1.5), lp_sweep(N(0.5), 0.35, 0.02)*env(int(SR*0.5), curve=2.5)), 0.6)
save("zone", cat(*[note(f, 0.14, "tri", curve=0.8) for f in [392, 494, 587]], note(784, 0.5, "tri")), 0.35)
# ---------- ambiente (Gate 5) ----------
def loop_fade(x, d=0.6):
    # emenda o fim no comeco (sem estalo ao repetir)
    n = int(SR * d); head = x[:n].copy()
    x = x[n:].copy(); x[-n:] = x[-n:] * np.linspace(1, 0, n) + head * np.linspace(0, 1, n)
    return x
d = 12.0; tt = t(d)
gust = 0.55 + 0.45 * np.sin(2*np.pi*tt/6.0) * np.sin(2*np.pi*tt/2.7 + 1.0)
wind = lp_sweep(N(d), 0.02, 0.05) * gust
save("amb_wind", loop_fade(wind))
cave = lowpass(lowpass(N(d), 0.01), 0.02) * (0.8 + 0.2*np.sin(2*np.pi*tt/5.0)) + 0.25*np.sin(2*np.pi*48*tt)*(0.6+0.4*np.sin(2*np.pi*tt/3.0))
save("amb_cave", loop_fade(cave))
# gota: "plip" que sobe de tom, com eco curto
d = 0.5; dr = sweep(900, 1700, 0.05, "sine") * env(int(SR*0.05), a=0.002, curve=2)
drip = np.zeros(int(SR*d)); drip[:len(dr)] += dr
for k, g in [(0.09, 0.35), (0.19, 0.15), (0.31, 0.06)]:
    i = int(SR*k); drip[i:i+len(dr)] += dr * g
save("drip", drip)
# passaros: piados curtos (frequencia sobe e desce rapido)
def chirp(f0, f1, d):
    tt = t(d); f = f0 + (f1 - f0) * np.sin(np.pi * tt / d)
    return np.sin(2*np.pi*np.cumsum(f)/SR) * env(len(tt), a=0.01, curve=1.5)
gap = lambda d: np.zeros(int(SR*d))
save("bird0", cat(chirp(2600, 3600, 0.07), gap(0.05), chirp(2700, 3800, 0.07), gap(0.05), chirp(2500, 3300, 0.1)))
save("bird1", cat(chirp(3200, 2200, 0.12), gap(0.08), chirp(3000, 2000, 0.16)))
save("bird2", cat(*[cat(chirp(3800, 4300, 0.04), gap(0.03)) for _ in range(5)]))
# combate dinamico: aviso do pisao (dois toques graves subindo) e esquiva (sopro rapido)
save("warning", cat(mix(note(150, 0.12, "square", 0.3, curve=0.8), 0.5*note(75, 0.12, "tri")), gap(0.05),
		mix(note(190, 0.16, "square", 0.3, curve=1.0), 0.5*note(95, 0.16, "tri"))))
save("dodge", lp_sweep(N(0.16), 0.08, 0.5) * env(int(SR*0.16), a=0.01, curve=1.6) + 0.25*sweep(500, 1300, 0.16, "sine")*env(int(SR*0.16), curve=2))
print("ok", sorted(os.listdir(out)))
# click, open, close, pickup, error, chest, equip, drop, confirm e step0..4 vem de
# tools/import_kenney_sfx.py (sons gravados, CC0).
