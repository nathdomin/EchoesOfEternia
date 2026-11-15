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
def save(name, x, vol=0.5):
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    fade = min(len(x), int(SR * 0.004)); x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype(np.int16)
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
save("pickup", cat(note(988, 0.05, duty=0.25, curve=0.5), note(1319, 0.11, duty=0.25)), 0.3)
d = 0.4; tt = t(d); f = 300 + 500 * tt / d + 60 * np.sin(2 * np.pi * 18 * tt)
save("potion", np.sin(2*np.pi*np.cumsum(f)/SR) * env(len(tt), a=0.02, curve=1.2), 0.4)
save("click", note(1800, 0.025, duty=0.5, curve=3), 0.2)
save("open", lp_sweep(N(0.12), 0.08, 0.25) * env(int(SR*0.12), a=0.02, curve=1.5), 0.22)
d = 0.38; sh = sweep(400, 1600, d, "sine") * env(int(SR*d), a=0.02, curve=1.3)
save("magic", mix(sh, 0.4*sweep(800, 3200, d, "tri")*env(int(SR*d), curve=2), 0.15*lowpass(N(d), 0.6)*env(int(SR*d))), 0.38)
save("explosion", mix(lp_sweep(N(0.6), 0.5, 0.03) * env(int(SR*0.6), a=0.002, curve=1.6), 0.8*sweep(120, 40, 0.4, "sine")*env(int(SR*0.4), curve=2)), 0.55)
save("heal", cat(*[mix(note(f, 0.12, "sine", curve=0.7), 0.3*note(f*2, 0.12, "tri", curve=1)) for f in [523, 659, 784]], note(1047, 0.3, "sine")), 0.36)
save("slam", mix(0.9*sweep(90, 30, 0.55, "sine")*env(int(SR*0.55), a=0.002, curve=1.5), lp_sweep(N(0.5), 0.35, 0.02)*env(int(SR*0.5), curve=2.5)), 0.6)
save("error", cat(note(160, 0.07, curve=0.3), np.zeros(int(SR*0.04)), note(130, 0.1, curve=0.5)), 0.25)
save("zone", cat(*[note(f, 0.14, "tri", curve=0.8) for f in [392, 494, 587]], note(784, 0.5, "tri")), 0.35)
print("ok", sorted(os.listdir(out)))
