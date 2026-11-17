# Icones 24x24 das armas de classe (pacote C), feitos com o proprio desenho
# da arma na mao do Ninja Adventure (CC0): ampliado 2x sem suavizar (pixel
# inteiro, sem girar: girar estraga o pixel art) e centralizado. O arco usa
# o icone Arrow.png do pacote. As variantes de raridade usam a cor do item
# (ItemData.tint), nao arquivos novos.
# Uso: python tools/gen_item_icons.py
from PIL import Image
import os
SRC = 'assets/characters/ninja/Weapons'
OUT = 'assets/ui/custom'
os.makedirs(OUT, exist_ok=True)
for name in ['Sword', 'MagicWand']:
    im = Image.open(os.path.join(SRC, name + '.png')).convert('RGBA')
    im = im.crop(im.getbbox())
    im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
    canvas = Image.new('RGBA', (24, 24), (0, 0, 0, 0))
    canvas.paste(im, ((24 - im.width) // 2, (24 - im.height) // 2), im)
    canvas.save(os.path.join(OUT, 'item_%s.png' % name.lower()))
    print('ok', name, im.size)
