"""Original deterministic invitation backgrounds; no external art assets."""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import math, random
OUT=Path(__file__).resolve().parents[1]/'assets/art';OUT.mkdir(parents=True,exist_ok=True)
FORMATS={'classic':1512,'story':1920,'square':1080}
PALETTES={'botanical':('#F6F3EB','#768775'),'midnight':('#172C34','#B9A275'),'rosewater':('#F8EFEC','#B2787B')}
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
 else:
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
 path=base/file;path.parent.mkdir(parents=True,exist_ok=True);ic.resize((size,size),Image.Resampling.LANCZOS).save(path)
