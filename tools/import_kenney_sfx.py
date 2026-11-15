# Importa os sons gravados do Kenney (CC0) usados no jogo (Gate 5).
# Fontes (OpenGameArt, CC0, autor Kenney - www.kenney.nl):
#   RPGsounds_Kenney.zip        https://opengameart.org/content/50-rpg-sound-effects
#   kenney_interfaceSounds.zip  https://opengameart.org/content/interface-sounds
# Uso: python tools/import_kenney_sfx.py <RPGsounds_Kenney.zip> <kenney_interfaceSounds.zip> audio/sfx
# Precisa de numpy e soundfile (pip install numpy soundfile).
# Cada som: mono, corta o silencio, nivela pelo volume percebido e grava .wav.
import io, os, sys, zipfile
import numpy as np, soundfile as sf

# nome no jogo -> (pacote, arquivo, volume alvo em dB RMS)
SOUNDS = {
	"click":   ("ui",  "Audio/click_003.ogg",          -22),
	"open":    ("rpg", "OGG/bookFlip1.ogg",            -22),  # janelas de pergaminho
	"close":   ("rpg", "OGG/bookClose.ogg",            -22),
	"pickup":  ("rpg", "OGG/handleSmallLeather.ogg",   -19),
	"chest":   ("rpg", "OGG/creak1.ogg",               -18),
	"equip":   ("rpg", "OGG/metalLatch.ogg",           -19),
	"drop":    ("rpg", "OGG/dropLeather.ogg",          -19),
	"error":   ("ui",  "Audio/error_008.ogg",          -20),
	"confirm": ("ui",  "Audio/confirmation_003.ogg",   -19),
	"step0":   ("rpg", "OGG/footstep00.ogg",           -27),
	"step1":   ("rpg", "OGG/footstep01.ogg",           -27),
	"step2":   ("rpg", "OGG/footstep02.ogg",           -27),
	"step3":   ("rpg", "OGG/footstep03.ogg",           -27),
	"step4":   ("rpg", "OGG/footstep04.ogg",           -27),
}


def load(zf: zipfile.ZipFile, name: str):
	for n in zf.namelist():
		if n.endswith(name):
			data, sr = sf.read(io.BytesIO(zf.read(n)), always_2d=True)
			return data.mean(axis=1), sr
	raise FileNotFoundError(name)


def trim(x, thr=0.004):
	idx = np.nonzero(np.abs(x) > thr)[0]
	return x[max(idx[0] - 32, 0): idx[-1] + 256] if len(idx) else x


def main() -> None:
	zips = {"rpg": zipfile.ZipFile(sys.argv[1]), "ui": zipfile.ZipFile(sys.argv[2])}
	out = sys.argv[3]
	for game_name, (pack, src, target) in SOUNDS.items():
		x, sr = load(zips[pack], src)
		x = trim(x)
		act = x[np.abs(x) > 0.01]
		rms = np.sqrt(np.mean(act ** 2)) if len(act) else 1.0
		x = x * (10 ** (target / 20.0) / rms)
		peak = np.max(np.abs(x))
		if peak > 0.89:
			x = x * (0.89 / peak)
		fade = min(len(x), int(sr * 0.005))
		x[-fade:] *= np.linspace(1, 0, fade)
		sf.write(os.path.join(out, game_name + ".wav"), x.astype(np.float32), sr, subtype="PCM_16")
		print("%-8s <- %s" % (game_name, src))


main()
