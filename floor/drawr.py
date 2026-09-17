from PIL import Image, ImageDraw
import sys
ns = {}; exec(open('/tmp/claude-502/floor/radial.py').read(), ns)
plan, CX, CY = ns['plan'], ns['CX'], ns['CY']
BG, CORR = (14,17,30), (198,170,140)
FIX = {"core": (232,226,214), "deck": (58,86,74), "bay": (44,52,70), "storage": (52,64,86),
       "decon": (96,66,92), "pad": (70,78,96)}
LIVE = (86,64,52)
ROOM = [(58,104,170),(46,132,120),(176,72,112),(96,60,150),(150,40,48),(52,96,60),(70,70,120),(128,48,96)]
def draw(seed, cell=9):
    hall, slots, fixed = plan(seed)
    pts = list(hall) + [p for c,_ in slots for p in c] + [p for v in fixed.values() for p in v]
    x0=min(x for x,_ in pts)-1; x1=max(x for x,_ in pts)+2
    y0=min(y for _,y in pts)-1; y1=max(y for _,y in pts)+2
    img = Image.new('RGB', ((x1-x0)*cell,(y1-y0)*cell), BG); d=ImageDraw.Draw(img)
    def box(x,y,c):
        px,py=(x-x0)*cell,(y-y0)*cell; d.rectangle([px,py,px+cell-1,py+cell-1],fill=c)
    for n,cs in fixed.items():
        for x,y in cs: box(x,y, LIVE if n.startswith("living") else FIX[n])
    for i,(cs,_) in enumerate(slots):
        for x,y in cs: box(x,y,ROOM[i%len(ROOM)])
    for x,y in hall: box(x,y,CORR)
    return img, len(slots), len(hall)
seeds=[int(s) for s in sys.argv[1:]] or [3,4,5,6]
imgs=[draw(s)[0] for s in seeds]
w=max(i.width for i in imgs); h=max(i.height for i in imgs)
sheet=Image.new('RGB',(w*2+24,h*2+24),(8,10,18))
for k,im in enumerate(imgs[:4]): sheet.paste(im,((k%2)*(w+24),(k//2)*(h+24)))
sheet.save('/tmp/claude-502/floor/radial.png')
print([draw(s)[1:] for s in seeds])
