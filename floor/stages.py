from PIL import Image, ImageDraw
import json, sys
plans = json.load(open('/tmp/claude-502/floor/plans.json'))
p = next(q for q in plans if q["seed"] == int(sys.argv[1]))
STAGES = [0, 6, 18, 40, 70, 100]
BG, CORR, DARK = (14,17,30), (198,170,140), (40,42,52)
FIX = {"core": (232,226,214), "deck": (58,86,74), "bay": (44,52,70), "storage": (52,64,86),
       "decon": (96,66,92), "pad": (70,78,96)}
LIVE = (86,64,52)
ROOM = [(58,104,170),(46,132,120),(176,72,112),(96,60,150),(150,40,48),(52,96,60),(70,70,120),(128,48,96)]
pts = [tuple(c) for c in p["base"]] + [tuple(c) for o in p["offices"] for c in o["cells"]+o["hall"]] \
    + [tuple(c) for cs in p["fixed"].values() for c in cs]
x0=min(x for x,_ in pts)-1; x1=max(x for x,_ in pts)+2
y0=min(y for _,y in pts)-1; y1=max(y for _,y in pts)+2
cell=7
def frame(n):
    img=Image.new('RGB',((x1-x0)*cell,(y1-y0)*cell),BG); d=ImageDraw.Draw(img)
    def box(x,y,c): d.rectangle([(x-x0)*cell,(y-y0)*cell,(x-x0)*cell+cell-1,(y-y0)*cell+cell-1],fill=c)
    # what is not lit yet, shown faint so the growth is readable
    for i,o in enumerate(p["offices"][n:], start=n):
        for x,y in o["cells"]: box(x,y,DARK)
    for nm,cs in p["fixed"].items():
        for x,y in cs: box(x,y, LIVE if nm.startswith("living") else FIX[nm])
    for x,y in p["base"]: box(x,y,CORR)
    for i,o in enumerate(p["offices"][:n]):
        for x,y in o["hall"]: box(x,y,CORR)
        for x,y in o["cells"]: box(x,y,ROOM[i%len(ROOM)])
    return img
imgs=[frame(n) for n in STAGES]
w,h=imgs[0].size
sheet=Image.new('RGB',(w*3+32,h*2+16),(8,10,18))
for k,im in enumerate(imgs): sheet.paste(im,((k%3)*(w+16),(k//3)*(h+16)))
sheet.save('/tmp/claude-502/floor/stages.png')
print("stages:", STAGES)
