from PIL import Image, ImageDraw, ImageFilter
import statistics
def inpaint(im, poly, mode):
    W,H=im.size
    m=Image.new('L',im.size,0); ImageDraw.Draw(m).polygon(poly,fill=255)
    xs=[p[0] for p in poly]; ys=[p[1] for p in poly]
    x0,y0,x1,y1=min(xs)-6,min(ys)-6,max(xs)+6,max(ys)+6
    px=im.load(); mp=m.load()
    inside=[(x,y) for y in range(y0,y1) for x in range(x0,x1) if mp[x,y]]
    if mode=='glyphs':
        med=[statistics.median(px[x,y][c] for x,y in inside) for c in range(3)]
        dark=Image.new('L',im.size,0); dp=dark.load()
        for x,y in inside:
            if sum(abs(px[x,y][c]-med[c]) for c in range(3))>22: dp[x,y]=255
        dark=dark.filter(ImageFilter.MaxFilter(9))
        m=Image.composite(dark,Image.new('L',im.size,0),m.filter(ImageFilter.MaxFilter(5)))
        mp=m.load()
    if mode=='hfill':
        for y in range(min(ys),max(ys)+1):
            a=px[min(xs)-1,y]; b=px[max(xs)+1,y]; L=max(xs)-min(xs)+2
            for x in range(min(xs),max(xs)+1):
                t=(x-min(xs)+1)/L; px[x,y]=tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
        return 0
    region=[(x,y) for y in range(y0,y1) for x in range(x0,x1) if mp[x,y]]
    ring=[px[x,y] for y in range(y0,y1) for x in range(x0,x1) if not mp[x,y]]
    bg=[statistics.median(v[c] for v in ring) for c in range(3)]
    val={p:list(bg) for p in region}
    S=set(region)
    for it in range(1500):
        new={}
        for (x,y) in region:
            acc=[0,0,0];n=0
            for q in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                v=val[q] if q in S else px[q]
                acc=[acc[i]+v[i] for i in range(3)];n+=1
            new[(x,y)]=[a/n for a in acc]
        val=new
    for p,v in val.items(): px[p]=tuple(int(round(c)) for c in v)
    return len(region)
jobs={
 '1-feed':[([(436,683),(557,659),(561,686),(438,704)],'glyphs')],
 '2-chat':[([(188,563),(323,568),(323,593),(188,588)],'glyphs'),([(676,2099),(1010,2099),(1010,2180),(676,2180)],'hfill')],
 '3-article':[([(106,505),(230,519),(229,547),(104,527)],'glyphs')],
}
for f,js in jobs.items():
    im=Image.open(f+'.jpg').convert('RGB')
    for poly,mode in js: print(f,mode,inpaint(im,poly,mode))
    im.save(f+'-fixed.jpg',quality=95)
