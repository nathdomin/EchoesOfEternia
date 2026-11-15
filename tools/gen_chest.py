# Bau 16x16 (fechado | aberto) no estilo Ninja Adventure: contorno escuro,
# madeira quente, ferragens douradas. Gera chest.png 32x16.
import sys
from PIL import Image
O=(28,18,22,255); W1=(150,82,46,255); W2=(196,118,62,255); W3=(232,160,90,255)
G1=(214,160,48,255); G2=(255,222,110,255); D=(70,36,30,255); IN=(46,24,26,255); T=(0,0,0,0)
def chest(opened):
    im=Image.new('RGBA',(16,16),T); p=im.putpixel
    def rect(x0,y0,x1,y1,c):
        for y in range(y0,y1+1):
            for x in range(x0,x1+1): p((x,y),c)
    # corpo (y 8..14)
    rect(1,8,14,14,O); rect(2,9,13,13,W1); rect(2,9,13,9,W2)
    for x in range(2,14,4): rect(x,10,x,13,D) if x>2 else None
    rect(2,13,13,13,D)
    rect(2,9,2,13,G1); rect(13,9,13,13,G1)
    if not opened:
        # tampa (y 3..8)
        rect(1,3,14,8,O); rect(2,4,13,7,W2); rect(2,4,13,4,W3); rect(3,3,12,3,O)
        rect(2,8,13,8,G1); rect(2,4,2,7,G1); rect(13,4,13,7,G1)
        rect(7,6,8,9,O); rect(7,7,8,8,G2)  # fecho
    else:
        # tampa aberta para tras (fina) e interior escuro com brilho
        rect(1,2,14,6,O); rect(2,3,13,5,W1); rect(2,3,13,3,W2); rect(2,5,13,5,G1)
        rect(2,7,13,8,IN); rect(1,7,1,8,O); rect(14,7,14,8,O)
        p((5,7),G2); p((9,7),G1); p((10,8),G2)
    return im
out=Image.new('RGBA',(32,16),T); out.paste(chest(False),(0,0)); out.paste(chest(True),(16,0))
out.save(sys.argv[1])
big=out.resize((256,128),Image.NEAREST); big.save(sys.argv[1].replace('.png','_big.png'))
