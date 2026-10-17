"""Original deterministic invitation backgrounds; no external art assets."""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import math, random
OUT=Path(__file__).resolve().parents[1]/'assets/art';OUT.mkdir(parents=True,exist_ok=True)
FORMATS={'classic':1512,'story':1920,'square':1080}
PALETTES={
    'botanical':('#F6F3EB','#768775'),
    'midnight':('#172C34','#B9A275'),
    'rosewater':('#F8EFEC','#B2787B'),
    'gilded':('#0F2A26','#C8A24B'),
    'terracotta':('#F7EFE7','#C87F5A'),
    'blush':('#FDF0F2','#E39AA8'),
    'confetti':('#FFF8EC','#F07A5F'),
    'littleone':('#EFF6FB','#F2B8C6'),
    'starlight':('#111A3A','#F0C878'),
}
S=2

def leaf(draw,x,y,angle,length,width,fill,outline=None):
 c,s=math.cos(angle),math.sin(angle)
 def tr(a,b):return ((x+a*c-b*s)*S,(y+a*s+b*c)*S)
 points=[]
 for i in range(31):
  t=i/30;points.append(tr(length*t,width*math.sin(math.pi*t)*0.5))
 for i in range(30,-1,-1):
  t=i/30;points.append(tr(length*t,-width*math.sin(math.pi*t)*0.5))
 draw.polygon(points,fill=fill)
 draw.line([tr(0,0),tr(length*.85,0)],fill=outline or fill,width=1)

def branch(draw,base,angle,length,color):
 x,y=base;c,s=math.cos(angle),math.sin(angle)
 pts=[]
 for i in range(81):
  t=i/80;pts.append(((x+c*length*t+math.sin(t*math.pi)*24)*S,(y+s*length*t)*S))
 draw.line(pts,fill=color,width=2,joint='curve')
 for i in range(2,11):
  t=i/12;xx=x+c*length*t+math.sin(t*math.pi)*24;yy=y+s*length*t
  for side in [-1,1]:
   a=angle+side*.78
   le=(1-t*.5)*65
   leaf(draw,xx,yy,a,le,le*.30,color)

def art(name,h):
 bg,ink=PALETTES[name];im=Image.new('RGB',(1080*S,h*S),bg)
 # Fine paper variation baked into the background, never behind the UI.
 rng=random.Random(113+ h);p=im.load();rgb=tuple(int(bg[i:i+2],16) for i in (1,3,5))
 for _ in range(75000):
  x=rng.randrange(im.width);y=rng.randrange(im.height);v=rng.choice([-4,-3,-2,2,3]);p[x,y]=tuple(max(0,min(255,c+v)) for c in rgb)
 d=ImageDraw.Draw(im,'RGBA')
 m=tuple(int(ink[i:i+2],16) for i in (1,3,5))
 def rgba(alpha):return (m[0],m[1],m[2],alpha)
 if name=='botanical':
  d.rectangle((64*S,64*S,1016*S,(h-64)*S),outline=(116,132,111,75),width=2)
  branch(d,(12,340),-.9,380,(91,116,90,140))
  branch(d,(65,150),-.26,335,(121,143,113,110))
  branch(d,(1065,h-330),2.22,365,(86,112,85,140))
  branch(d,(1030,h-110),2.95,305,(125,144,115,100))
  # Small pressed-flower seal.
  cx,cy=540,h*(.105 if h!=1080 else .075)
  for a in range(0,360,45):
   aa=math.radians(a);leaf(d,cx,cy,aa,23,14,(110,128,103,170))
  d.ellipse(((cx-5)*S,(cy-5)*S,(cx+5)*S,(cy+5)*S),fill=(176,148,97,220))
 elif name=='midnight':
  for inset,alpha in [(54,180),(69,80)]:
   d.rectangle((inset*S,inset*S,(1080-inset)*S,(h-inset)*S),outline=(185,162,117,alpha),width=2)
  # A celestial engraved fan, confined to the corners.
  for i in range(11):
   r=70+i*17
   d.arc(((-r+72)*S,(-r+72)*S,(r+72)*S,(r+72)*S),0,90,fill=(185,162,117,80),width=2)
   d.arc(((1008-r)*S,(h-72-r)*S,(1008+r)*S,(h-72+r)*S),180,270,fill=(185,162,117,80),width=2)
  cx,cy=540,h*(.112 if h!=1080 else .075)
  d.ellipse(((cx-31)*S,(cy-31)*S,(cx+31)*S,(cy+31)*S),outline=(185,162,117,200),width=2)
  for a in [0,90,180,270]:
   aa=math.radians(a);leaf(d,cx,cy,aa,21,8,(185,162,117,210))
 elif name=='rosewater':
  wash=Image.new('RGBA',im.size);w=ImageDraw.Draw(wash)
  for cx,cy,rx,ry in [(25,100,270,270),(1025,h-50,290,310),(1050,220,120,220)]:
   w.ellipse(((cx-rx)*S,(cy-ry)*S,(cx+rx)*S,(cy+ry)*S),fill=(196,121,127,24))
  wash=wash.filter(ImageFilter.GaussianBlur(50*S));im=Image.alpha_composite(im.convert('RGBA'),wash).convert('RGB');d=ImageDraw.Draw(im,'RGBA')
  for x in [64,78]:
   d.rounded_rectangle((x*S,x*S,(1080-x)*S,(h-x)*S),radius=460*S,outline=(170,118,119,100),width=2)
  cx,cy=540,h*(.11 if h!=1080 else .075)
  for a in [-.6,.6,2.54,3.74]:leaf(d,cx,cy,a,29,13,(178,120,122,200))
  d.line(((cx-80)*S,cy*S,(cx-42)*S,cy*S),fill=(178,120,122,150),width=2)
  d.line(((cx+42)*S,cy*S,(cx+80)*S,cy*S),fill=(178,120,122,150),width=2)
 elif name=='gilded':
  # Deep emerald card with a gold double frame and foil corner sprays.
  for inset,alpha in [(52,150),(66,70)]:
   d.rectangle((inset*S,inset*S,(1080-inset)*S,(h-inset)*S),outline=rgba(alpha),width=2)
  branch(d,(28,300),-.90,340,rgba(150))
  branch(d,(66,250),-.30,300,rgba(110))
  branch(d,(1052,h-300),2.24,340,rgba(150))
  branch(d,(1014,h-250),2.84,300,rgba(110))
  cx,cy=540,h*(.125 if h!=1080 else .085)
  d.ellipse(((cx-56)*S,(cy-56)*S,(cx+56)*S,(cy+56)*S),outline=rgba(210),width=2)
  d.ellipse(((cx-44)*S,(cy-44)*S,(cx+44)*S,(cy+44)*S),outline=rgba(120),width=1)
  for a in range(0,360,60):
   aa=math.radians(a);leaf(d,cx,cy,aa,19,7,rgba(190))
  d.ellipse(((cx-5)*S,(cy-5)*S,(cx+5)*S,(cy+5)*S),fill=rgba(235))
 elif name=='terracotta':
  # Warm desert arches rising near the top with a low horizon and sun rays.
  cy=h*.28;rr=h*.205
  d.arc((((540-rr)*S,(cy-rr)*S),((540+rr)*S,(cy+rr)*S)),180,360,fill=rgba(120),width=2)
  for r in range(int(rr*.5),int(rr),int(rr*.14)):
   d.arc((((540-r)*S,(cy-r)*S),((540+r)*S,(cy+r)*S)),180,360,fill=rgba(60),width=2)
  for a in range(20,161,20):
   aa=math.radians(a)
   d.line((540*S,0,(540+math.cos(aa)*h*.17)*S,(math.sin(aa)*h*.17)*S),fill=rgba(45),width=2)
  d.line((80*S,(h-92)*S,1000*S,(h-92)*S),fill=rgba(90),width=2)
  d.arc(((120*S,(h-h*.18)*S),(960*S,(h+h*.10)*S)),180,360,fill=rgba(110),width=2)
  branch(d,(70,h-230),-1.2,240,rgba(120))
  branch(d,(1010,h-230),-1.95,240,rgba(120))
 elif name=='blush':
  wash=Image.new('RGBA',im.size);wd=ImageDraw.Draw(wash)
  for cx,cy,rx,ry in [(30,80,250,250),(1050,h-40,280,300),(1050,180,120,220),(40,h-140,150,180)]:
   wd.ellipse(((cx-rx)*S,(cy-ry)*S,(cx+rx)*S,(cy+ry)*S),fill=(227,154,168,26))
  wash=wash.filter(ImageFilter.GaussianBlur(46*S));im=Image.alpha_composite(im.convert('RGBA'),wash).convert('RGB');d=ImageDraw.Draw(im,'RGBA')
  for x in [58,70]:
   d.rounded_rectangle((x*S,x*S,(1080-x)*S,(h-x)*S),radius=420*S,outline=(190,120,132,90),width=2)
  rp=random.Random(7+h)
  for _ in range(44):
   px=rp.uniform(50,1030);py=rp.uniform(50,h-50)
   if 250<px<830 and h*.26<py<h*.80: continue
   leaf(d,px,py,rp.uniform(0,6.28),rp.uniform(12,22),rp.uniform(5,9),(214,150,164,150))
 elif name=='confetti':
  cols=[(240,122,95),(120,170,150),(240,190,90),(150,140,210),(230,120,160),(90,150,200)]
  rp=random.Random(21+h)
  def conf(px,py):
   c=rp.choice(cols);a=rp.uniform(0,6.28);sz=rp.uniform(7,14)
   cc,ss=math.cos(a),math.sin(a)
   def tr(ux,uy):return ((px+ux*cc-uy*ss)*S,(py+ux*ss+uy*cc)*S)
   d.polygon([tr(-sz,-sz*.42),tr(sz,-sz*.42),tr(sz,sz*.42),tr(-sz,sz*.42)],fill=(c[0],c[1],c[2],190))
  for _ in range(190):
   px=rp.uniform(36,1044);py=rp.uniform(36,h-36)
   edge=px<210 or px>870 or py<h*.20 or py>h*.82
   if not edge and rp.random()<0.84: continue
   conf(px,py)
  d.rectangle((38*S,38*S,1042*S,(h-38)*S),outline=(46,58,89,55),width=2)
 elif name=='littleone':
  cloud=(255,255,255,225);star=(242,184,198,210)
  def cloud_at(cx,cy,sc):
   for dx,dy,r in [(-62,2,44),(0,-16,58),(62,2,44),(32,12,40),(-32,12,40)]:
    d.ellipse(((cx+(dx-r)*sc)*S,(cy+(dy-r)*sc)*S,(cx+(dx+r)*sc)*S,(cy+(dy+r)*sc)*S),fill=cloud)
  cloud_at(190,h*.13,1.0);cloud_at(900,h*.10,.82);cloud_at(540,h*.055,.6)
  cloud_at(150,h*.90,.9);cloud_at(540,h*.965,1.25);cloud_at(935,h*.92,.95)
  rp=random.Random(5+h)
  for _ in range(42):
   px=rp.uniform(60,1020);py=rp.uniform(60,h-60)
   if 250<px<830 and h*.24<py<h*.82: continue
   d.ellipse(((px-3)*S,(py-3)*S,(px+3)*S,(py+3)*S),fill=star)
  bx,by=960,h*.22
  d.line((bx*S,(by+34)*S,(bx-8)*S,(by+140)*S),fill=(150,170,190,150),width=2)
  d.ellipse(((bx-27)*S,(by-33)*S,(bx+27)*S,(by+33)*S),fill=(242,184,198,220))
 elif name=='starlight':
  gold=(240,200,120,200)
  rp=random.Random(9+h)
  for _ in range(150):
   px=rp.uniform(40,1040);py=rp.uniform(40,h-40)
   r=rp.choice([1.2,1.8,2.6,3.4])
   d.ellipse(((px-r)*S,(py-r)*S,(px+r)*S,(py+r)*S),fill=gold)
  for _ in range(16):
   px=rp.uniform(70,1010);py=rp.uniform(70,h-70);r=rp.uniform(6,11)
   d.line((px*S,(py-r)*S,px*S,(py+r)*S),fill=(240,200,120,170),width=1)
   d.line(((px-r)*S,py*S,(px+r)*S,py*S),fill=(240,200,120,170),width=1)
  cx,cy=540,h*(.115 if h!=1080 else .08)
  d.ellipse(((cx-52)*S,(cy-52)*S,(cx+52)*S,(cy+52)*S),outline=(240,200,120,210),width=2)
  d.ellipse(((cx-40)*S,(cy-40)*S,(cx+40)*S,(cy+40)*S),outline=(240,200,120,110),width=1)
  for a in range(30,360,60):
   aa=math.radians(a);leaf(d,cx,cy,aa,16,6,(240,200,120,150))
  pts=[(150,h*.80),(300,h*.725),(430,h*.845),(760,h*.80),(930,h*.71),(1000,h*.865)]
  for i in range(len(pts)-1):
   d.line((pts[i][0]*S,pts[i][1]*S,pts[i+1][0]*S,pts[i+1][1]*S),fill=(240,200,120,70),width=1)
  for (px,py) in pts:
   d.ellipse(((px-3)*S,(py-3)*S,(px+3)*S,(py+3)*S),fill=(240,200,120,190))
  for inset in [44,58]:
   d.rectangle((inset*S,inset*S,(1080-inset)*S,(h-inset)*S),outline=(240,200,120,70),width=2)
 return im

for name in PALETTES:
 for fmt,h in FORMATS.items():
  im=art(name,h);path=OUT/f'{name}_{fmt}.png';im.save(path,optimize=True)
  if fmt=='classic':
   im.thumbnail((360,504));im.save(OUT/f'{name}_thumb.png',optimize=True)
  print(path.name,path.stat().st_size)
# Local brand icon for web and mobile; no Flutter default branding.
ic=Image.new('RGB',(512,512),'#3F5147');d=ImageDraw.Draw(ic)
d.rounded_rectangle((58,58,454,454),radius=100,outline='#DFE4D3',width=3)
for a in [0,math.pi/2,math.pi,3*math.pi/2]:leaf(d,128,128,a,42,17,'#DFE4D3')
d.line((256,157,256,355),fill='#F6F3EB',width=17)
d.line((207,157,305,157),fill='#F6F3EB',width=10)
d.line((207,355,305,355),fill='#F6F3EB',width=10)
base=OUT.parents[1]
for file,size in [('web/favicon.png',32),('web/icons/Icon-192.png',192),('web/icons/Icon-512.png',512),('web/icons/Icon-maskable-192.png',192),('web/icons/Icon-maskable-512.png',512)]:
 path=base/file;path.parent.mkdir(parents=True,exist_ok=True)
 ic.resize((size,size),Image.Resampling.LANCZOS).save(path)
