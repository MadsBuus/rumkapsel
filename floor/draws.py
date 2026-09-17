from PIL import Image, ImageDraw
import sys
ns={}; exec(open('/tmp/claude-502/floor/floorplan.py').read(), ns)
# The game's own palette, sampled off its screens (LAYOUT.md).
BG   = (0x0E,0x11,0x17)   # space
CORR = (0x81,0x65,0x5B)   # hallway floor
DARK = (0x43,0x42,0x42)   # a room that is not lit yet
EDGE = (0x2A,0x29,0x29)   # wall strips and tile borders
FIX  = {"plaza":CORR, "west":CORR, "south":CORR,
        "storage":(0x4E,0xA9,0xA0), "deck":(0x7C,0xA8,0x2E), "pad":(0xD3,0x6B,0x25),
        "decon":(0xB5,0x53,0x83), "airlock":(0x43,0x42,0x42), "hangar":(0x2A,0x29,0x29)}
Q    = (0xE0,0xA1,0x1C)   # the quarters
ROOM = [(0x2C,0x76,0xB4),(0xD3,0x6B,0x25),(0xE0,0xA1,0x1C),(0xB5,0x53,0x83),(0x7C,0xA8,0x2E),(0x4E,0xA9,0xA0)]

theme=sys.argv[1]; seeds=[int(s) for s in sys.argv[2:]]
def draw(seed,cell=11):
    hall,slots,quarters,fixed,mono,_=ns['plan'](theme,seed)
    pts=list(hall)+[p for cs in slots for p in cs]+[p for v in quarters.values() for p in v]+[p for v in fixed.values() for p in v]
    x0=min(x for x,_ in pts)-1;x1=max(x for x,_ in pts)+2
    y0=min(y for _,y in pts)-1;y1=max(y for _,y in pts)+2
    img=Image.new('RGB',((x1-x0)*cell,(y1-y0)*cell),BG);d=ImageDraw.Draw(img)
    def box(x,y,c,tiled=True):
        px,py=(x-x0)*cell,(y-y0)*cell
        # The hallway is flat floor; rooms and blocks are tiled, as the game draws them.
        d.rectangle([px,py,px+cell-1,py+cell-1],fill=c,outline=EDGE if tiled else None)
    for n,cs in fixed.items():
        for x,y in cs: box(x,y,FIX[n], tiled=n not in ("plaza","west","south"))
    for cs in quarters.values():
        for x,y in cs: box(x,y,Q)
    for i,cs in enumerate(slots):
        for x,y in cs: box(x,y,ROOM[i%len(ROOM)])
    for x,y in hall: box(x,y,CORR,tiled=False)
    box(mono[0],mono[1],(240,240,240))
    return img
imgs=[draw(s) for s in seeds]
w=max(i.width for i in imgs);h=max(i.height for i in imgs)
sheet=Image.new('RGB',(w*2+24,h*2+24),(8,10,18))
for k,im in enumerate(imgs[:4]): sheet.paste(im,((k%2)*(w+24),(k//2)*(h+24)))
sheet.save('/tmp/claude-502/floor/station.png')
print("ok")
