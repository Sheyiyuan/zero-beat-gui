#!/usr/bin/env python3
"""Build editable, offline SVG product design boards from shared tokens."""
from pathlib import Path
from html import escape
import json

ROOT = Path(__file__).resolve().parent
TOKENS = {
  'color': {'canvas':'#F7F3F5','surface':'#FFFFFF','surfaceMuted':'#F0E8EC','text':'#2B262B','muted':'#6B5F66','line':'#DFD4DA','accent':'#B02A52','accentSoft':'#F7DBE2','brandRed':'#FF5555','positive':'#1A7F37','warning':'#8A5A00','danger':'#B42318','focus':'#B02A52'},
  'typography': {'body':'Noto Sans CJK SC, sans-serif','display':'Source Han Serif SC, Noto Serif CJK SC, serif','utility':'DejaVu Sans Mono, monospace','scale':[11,12,13,14,16,18,20,24,28,32,40]},
  'spacing':[4,8,12,16,24,32,40,48,64],
  'radius':{'control':8,'surface':12,'cover':8,'sheet':24},
  'layout':{'desktop':{'width':1440,'height':960,'sidebar':224,'playerHeight':112,'contentPadding':40,'tableRow':64},'android':{'width':390,'height':844,'horizontalPadding':24,'minTouchTarget':48,'bottomNavigation':72,'miniPlayer':64}},
  'interaction':{'focusStroke':2,'focusOffset':3,'reducedMotion':'remove decorative transitions; preserve state changes','currentAuthor':'u outside text input; one author opens directly; multiple authors open chooser','commentAuthor':'click avatar or author name; no dedicated shortcut','desktopInput':'mouse first; common shortcuts only','mobileInput':'separate touch design with bottom navigation, sheets and system back','syncAccountsDefault':False}
}
(ROOT/'tokens.json').write_text(json.dumps(TOKENS,ensure_ascii=False,indent=2)+'\n')
C=TOKENS['color']; BODY=TOKENS['typography']['body']; DISP=TOKENS['typography']['display']; MONO=TOKENS['typography']['utility']
class SVG:
  def __init__(self,w=1440,h=960,title='零拍 GUI 设计预览'):
    self.w,self.h=w,h
    self.a=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="title desc">',f'<title id="title">{escape(title)}</title><desc id="desc">零拍图形客户端静态设计预览。所有歌曲、人物、评论和封面均为虚构示例，非已上线功能。</desc>']
  def raw(self,s): self.a.append(s)
  def rect(self,x,y,w,h,fill='surface',r=0,stroke=None,sw=1):
    self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{C.get(fill,fill)}"'+(f' stroke="{C.get(stroke,stroke)}" stroke-width="{sw}"' if stroke else '')+'/>')
  def line(self,x1,y1,x2,y2,color='line',sw=1): self.raw(f'<path d="M{x1} {y1}H{x2}" fill="none" stroke="{C.get(color,color)}" stroke-width="{sw}"/>' if y1==y2 else f'<path d="M{x1} {y1}L{x2} {y2}" fill="none" stroke="{C.get(color,color)}" stroke-width="{sw}"/>')
  def text(self,x,y,t,size=14,color='text',weight=400,anchor='start',font=None): self.raw(f'<text x="{x}" y="{y}" font-family="{escape(font or BODY)}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" fill="{C.get(color,color)}">{escape(str(t))}</text>')
  def circle(self,x,y,r,fill='surfaceMuted',stroke=None): self.raw(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{C.get(fill,fill)}"'+(f' stroke="{C.get(stroke,stroke)}"' if stroke else '')+'/>')
  def icon(self,n,x,y,s=20,color='muted'):
    paths={'search':'M10 3a7 7 0 1 0 0 14a7 7 0 0 0 0-14M15 15l6 6','library':'M4 3v18M9 3v18M14 4l5-1 4 17-5 1z','compass':'M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20M16 8l-3 5-5 3 3-5z','radio':'M4 8h16v13H4zM7 8l11-5M8 13v4M12 13h5M12 17h5','download':'M12 3v12M7 10l5 5 5-5M4 17v4h16v-4','list':'M8 5h13M8 12h13M8 19h13M3 5h1M3 12h1M3 19h1','user':'M12 3a4 4 0 1 0 0 8a4 4 0 0 0 0-8M4 22v-3a8 7 0 0 1 16 0v3','settings':'M12 8a4 4 0 1 0 0 8a4 4 0 0 0 0-8M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2','heart':'M12 21L3 12C-2 5 7 0 12 6C17 0 26 5 21 12z','play':'M7 3l14 9L7 21z','pause':'M8 4v16M16 4v16','next':'M5 4l12 8-12 8zM20 4v16','previous':'M19 4L7 12l12 8zM4 4v16','volume':'M3 9h4l6-5v16l-6-5H3zM17 8q6 4 0 8','chevron':'M9 4l8 8-8 8','back':'M15 4l-8 8 8 8','down':'M5 8l7 7 7-7','chat':'M3 3h18v14H9l-6 4z','repeat':'M4 8h14l-3-3M20 16H6l3 3M4 8v7M20 16V9','plus':'M12 4v16M4 12h16','close':'M5 5l14 14M5 19L19 5','check':'M4 12l5 5L20 6','sync':'M3 10a9 9 0 0 1 16-5l2 3M21 2v6h-6M21 14a9 9 0 0 1-16 5l-2-3M3 22v-6h6','music':'M9 18V5l11-2v13M9 5l11-2M9 18a3 2 0 1 1-6 0a3 2 0 1 1 6 0M20 16a3 2 0 1 1-6 0a3 2 0 1 1 6 0','clock':'M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20M12 6v6l4 3','more':'M4 12h1M11 12h1M18 12h1','external':'M10 4H4v16h16v-6M14 3h7v7M21 3L10 14','keyboard':'M2 5h20v14H2zM6 9h1M11 9h1M16 9h1M6 14h12'}
    self.raw(f'<g transform="translate({x} {y}) scale({s/24})" fill="none" stroke="{C.get(color,color)}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="{paths[n]}"/></g>')
  def button(self,x,y,w,label,primary=False,icon=None,h=40,focus=False):
    self.rect(x,y,w,h,'accent' if primary else 'surface',8,None if primary else 'line')
    if focus:self.rect(x-3,y-3,w+6,h+6,'none',11,'focus',2)
    if icon:self.icon(icon,x+13,y+(h-20)/2,20,'surface' if primary else 'text')
    self.text(x+w/2+(10 if icon else 0),y+h/2+5,label,14,'surface' if primary else 'text',500,'middle')
  def pill(self,x,y,label,w=None,active=False):
    w=w or len(label)*14+24; self.rect(x,y,w,30,'accentSoft' if active else 'surfaceMuted',15)
    self.text(x+w/2,y+20,label,12,'accent' if active else 'muted',500,'middle')
  def cover(self,x,y,s,variant=0):
    cols=[('#D9E4E5','#4C6A73','#B9CFCE'),('#E8D9D0','#9B695E','#C6B1AA'),('#DAD9E7','#686478','#B7AEC6'),('#D7E0D6','#55745B','#A7BBA6')]
    bg,fg,mid=cols[variant%len(cols)]; self.rect(x,y,s,s,bg,8)
    self.raw(f'<path d="M{x} {y+s*.75}Q{x+s*.45} {y+s*.2} {x+s} {y+s*.55}V{y+s-8}Q{x+s} {y+s} {x+s-8} {y+s}H{x+8}Q{x} {y+s} {x} {y+s-8}Z" fill="{mid}"/>')
    self.circle(x+s*.7,y+s*.26,s*.105,fg)
    self.raw(f'<path d="M{x} {y+s*.86}Q{x+s*.5} {y+s*.6} {x+s} {y+s*.86}V{y+s-8}Q{x+s} {y+s} {x+s-8} {y+s}H{x+8}Q{x} {y+s} {x} {y+s-8}Z" fill="{fg}"/>')
    if s>100:self.text(x+16,y+28,['夜 行','余 温','回 声','山 间'][variant%4],max(12,s/15),fg,500,font=DISP)
  def avatar(self,x,y,size=40,letter='林',v=0):
    self.circle(x+size/2,y+size/2,size/2,['#E9D8DF','#DDE6E4','#E2DEEC'][v%3]);self.text(x+size/2,y+size*.66,letter,size*.36,'accent' if v==0 else 'muted',500,'middle')
  def save(self,name): (ROOT/'screens'/name).write_text('\n'.join(self.a+['</svg>'])+'\n')

def sidebar(s,active='曲库'):
  s.rect(0,0,1440,960,'canvas');s.rect(0,0,224,848,'surface')
  s.circle(41,47,14,'accent');s.line(34,40,34,54,'surface',3);s.line(42,36,42,58,'surface',3);s.line(50,43,50,51,'surface',3)
  s.text(68,56,'零拍',26,'text',600);s.text(26,91,'音乐，留在你的节奏里。',11,'muted')
  items=[('曲库','library'),('发现','compass'),('播客 / 电台','radio'),('下载','download')]
  for i,(name,ico) in enumerate(items):
    y=126+i*52
    if name==active:s.rect(16,y,192,44,'accentSoft',8);s.rect(16,y+13,3,18,'accent',1)
    s.icon(ico,32,y+12,20,'accent' if name==active else 'muted');s.text(64,y+28,name,14,'accent' if name==active else 'text',500 if name==active else 400)
  s.text(32,370,'我的歌单',12,'muted',500);s.icon('plus',177,354,18)
  for i,(name,count) in enumerate([('喜欢的音乐','128'),('夜行电台','36'),('慢下来','24'),('待听清单','12')]):
    s.icon('heart' if i==0 else 'list',32,394+i*43,18);s.text(64,409+i*43,name,13);s.text(191,409+i*43,count,11,'muted',anchor='end',font=MONO)
  s.line(24,724,200,724);s.avatar(28,745,36,'我');s.text(76,760,'本机曲库',13,weight=500);s.text(76,779,'已连接网易云',11,'muted');s.icon('settings',181,752,20)
  s.text(28,820,'设计预览 · 虚构示例内容',10,'muted')
  s.icon('back',258,38,20);s.icon('chevron',294,38,20,'line');s.rect(338,24,492,44,'surface',10,'line');s.icon('search',353,36,20);s.text(386,52,'搜索歌曲、视频、歌手',13,'muted');s.text(805,52,'/',14,'muted',font=MONO)
  s.icon('sync',1240,37,20);s.text(1270,52,'已同步',12,'muted');s.icon('more',1384,38,20)

def player(s,title='凌晨一点半',artist='林屿 · 陈澈',program=False):
  s.rect(0,848,1440,112,'surface');s.rect(0,848,1440,2,'line');s.rect(0,848,520,2,'accent');s.circle(520,849,3,'accent')
  s.cover(24,872,64,1 if program else 0);s.text(104,895,title,15,weight=600);s.text(104,921,artist,12,'muted');s.icon('down',104+len(artist)*12+5,908,15);s.icon('heart',290,893,21)
  s.icon('repeat',536,893,22);s.icon('previous',592,891,24);s.circle(668,904,25,'accent');s.icon('pause',656,892,24,'surface');s.icon('next',720,891,24)
  s.text(790,909,'01:42 / 04:36',11,'muted',font=MONO);s.icon('volume',1080,894,22);s.rect(1116,903,82,3,'line',2);s.rect(1116,903,56,3,'muted',2);s.circle(1172,904,4,'muted');s.text(1225,910,'歌词',13,'accent');s.icon('list',1294,894,22);s.text(1326,909,'12',11,'muted',font=MONO);s.icon('external',1382,894,20)
  s.text(104,943,'作者主页  u',10,'muted');s.text(656,946,'空格 暂停',10,'muted',anchor='middle')

def rows(s,x,y,w,items,focus=-1,playing=-1):
  s.text(x+24,y-16,'#',11,'muted',font=MONO);s.text(x+62,y-16,'歌曲 / 作者',11,'muted');s.text(x+w-230,y-16,'来源',11,'muted');s.text(x+w-70,y-16,'时长',11,'muted')
  for i,(title,artist,source,duration) in enumerate(items):
    yy=y+i*64
    if i==playing:s.rect(x,yy,w,60,'surfaceMuted',8);s.rect(x,yy+16,3,28,'accent',1)
    if i==focus:s.rect(x-3,yy-3,w+6,66,'none',11,'focus',2)
    if i==playing:s.icon('pause',x+17,yy+21,17,'accent')
    else:s.text(x+25,yy+35,f'{i+1:02}',11,'muted',anchor='middle',font=MONO)
    s.text(x+62,yy+25,title,14,'accent' if i==playing else 'text',500)
    s.text(x+62,yy+46,artist,11,'muted');s.pill(x+w-240,yy+15,source,72)
    s.text(x+w-48,yy+35,duration,11,'muted',anchor='end',font=MONO);s.icon('more',x+w-30,yy+22,18)
    if i!=playing:s.line(x+14,yy+63,x+w-8,yy+63)

SONGS=[('凌晨一点半','林屿 · 陈澈','网易云','04:36'),('晚风经过站台','南岸','B 站','05:12'),('把日子折成信','林屿','网易云','03:48'),('房间里的小宇宙','陈澈','网易云','04:09'),('一场缓慢的雨','声响档案','B 站','07:24'),('离岛来信','安禾','网易云','03:56')]

s=SVG(title='零拍桌面 · 曲库与播放队列');sidebar(s);player(s)
s.text(264,125,'曲库',28,weight=600);s.text(264,153,'每个平台，放进同一份歌单。',13,'muted')
s.cover(264,182,144,0);s.text(432,211,'本地歌单',11,'muted');s.text(432,251,'夜行电台',32,weight=600,font=DISP);s.text(433,282,'36 首 · 2 小时 18 分 · 网易云 / B 站',12,'muted');s.button(432,302,124,'全部播放',True,'play');s.button(568,302,108,'添加歌曲',icon='plus');s.icon('more',706,311,22)
s.line(1088,100,1088,814);s.text(1120,127,'接下来播放',16,weight=600);s.text(1395,127,'12 首',11,'muted',anchor='end')
for i,(t,a,_,d) in enumerate(SONGS[1:5]):
  yy=166+i*90;s.cover(1120,yy,48,i+1);s.text(1182,yy+21,t,13,weight=500);s.text(1182,yy+42,a,11,'muted')
s.line(1120,557,1400,557);s.text(1120,594,'正在播放的作者',12,'muted');s.avatar(1120,616,36,'林');s.text(1168,639,'林屿',13);s.icon('chevron',1370,624,17);s.avatar(1120,672,36,'陈',1);s.text(1168,695,'陈澈',13);s.icon('chevron',1370,680,17);s.text(1120,752,'u  选择作者主页',11,'muted',font=MONO)
s.pill(264,374,'全部',60,True);s.pill(334,374,'网易云',76);s.pill(420,374,'B 站',62);s.rect(812,374,236,32,'surface',8,'line');s.icon('search',824,382,17);s.text(853,396,'在歌单中查找',11,'muted')
rows(s,264,447,784,SONGS,focus=1,playing=0);s.save('01-desktop-library.svg')

s=SVG(title='零拍桌面 · 正在播放与歌词');sidebar(s);player(s)
s.text(264,126,'正在播放',22,weight=600);s.text(1396,126,'返回曲库',12,'muted',anchor='end')
s.cover(294,204,352,0);s.text(294,612,'凌晨一点半',32,weight=600,font=DISP);s.text(294,653,'林屿 · 陈澈',16,'muted');s.icon('down',420,635,20);s.pill(294,677,'网易云',76);s.button(294,733,130,'添加到歌单',icon='plus');s.button(436,733,104,'下载',icon='download')
s.text(760,197,'歌词',14,'accent',600);s.text(832,197,'评论',14,'muted');s.text(904,197,'相似歌曲',14,'muted');s.line(760,212,789,212,'accent',3)
lyric=[('街角最后一盏灯',284,'muted',20),('在雨里慢慢安静',348,'muted',20),('我们把一天放下',424,'text',24),('让夜晚轻轻经过',496,'accent',28),('还有没说完的话',572,'text',24),('留给明天的晨风',640,'muted',20),('此刻只听见心跳',704,'muted',20)]
for t,y,c,z in lyric:s.text(760,y,t,z,c,500 if c=='accent' else 400,font=DISP if c=='accent' else BODY)
s.rect(731,472,3,30,'accent',2);s.text(760,787,'逐字滚动',11,'muted');s.text(900,787,'歌词偏移  0.0 s',11,'muted');s.text(1375,787,'跟随播放',11,'accent',anchor='end');s.save('02-desktop-playing.svg')

s=SVG(title='零拍桌面 · B 站评论与相关推荐');sidebar(s,'发现');player(s,'晚风经过站台','南岸')
s.text(264,126,'评论与相关推荐',24,weight=600);s.cover(264,152,64,1);s.text(348,178,'晚风经过站台',20,weight=600);s.text(348,205,'南岸  ›',13,'muted');s.pill(1216,166,'B 站视频',132)
s.text(264,261,'评论',18,weight=600);s.text(870,261,'只读评论',11,'muted',anchor='end')
s.rect(264,284,608,44,'surfaceMuted',8);s.text(282,312,'当前为预览评论，登录 B 站后可查看更多。',12,'muted');s.text(843,312,'登录',12,'accent',600,'end')
comments=[('晚','晚归的人','2026-11-16 · 18:24','这段前奏一响，就想起晚上坐最后一班公交。','窗外的灯一盏一盏往后退，刚好到家。','128'),('小','小岛来信','2026-11-16 · 16:03','听到这里的时候，把今天没做完的事先放下了。','明天再继续。','64'),('纸','纸飞机','2026-11-15 · 22:19','用耳机听，能听见很轻的雨声。','谢谢这首歌陪我走过今天。','32')]
for i,(letter,n,date,l1,l2,likes) in enumerate(comments):
  y=356+i*136;s.avatar(264,y,36,letter,i);s.text(314,y+16,n,13,weight=500);s.icon('chevron',314+len(n)*13+7,y+2,14);s.text(314,y+37,date,10,'muted');s.text(314,y+67,l1,13);s.text(314,y+91,l2,13);s.text(843,y+15,'赞 '+likes,10,'muted',anchor='end');s.line(314,y+113,871,y+113)
s.text(264,806,'评论仅供浏览',11,'muted');s.text(870,806,'第 1 页 · 登录后查看更多',11,'muted',anchor='end')
s.line(912,240,912,810);s.text(952,261,'相关推荐',18,weight=600);s.text(1398,261,'4 个视频',11,'muted',anchor='end')
for i,(t,a,_,d) in enumerate([('窗边的雨声','南岸','B 站','06:24'),('日落之后，慢慢走','声响档案','B 站','08:13'),('城市醒来之前','安禾','B 站','04:58'),('一场缓慢的雨','声响档案','B 站','07:24')]):
  y=296+i*118;s.cover(952,y,88,i+1);s.text(1058,y+24,t,14,weight=500);s.text(1058,y+48,a+' · '+d,11,'muted');s.text(1058,y+76,'播放',12,'accent');s.text(1110,y+76,'加入队列',12,'muted');s.icon('more',1371,y+55,19)
s.save('03-desktop-comments.svg')

s=SVG(title='零拍桌面 · 歌手主页');sidebar(s,'发现');player(s)
s.text(264,123,'作者主页',14,'muted');s.avatar(264,162,136,'林');s.text(432,187,'歌手 · 网易云',12,'muted');s.text(432,237,'林屿',36,weight=600,font=DISP);s.text(432,275,'唱一些日常，记录沿途的声音。',14,'muted');s.text(432,307,'从「凌晨一点半」进入',11,'muted');s.button(1184,228,176,'播放热门作品',True,'play')
s.text(264,377,'热门作品',17,'accent',600);s.text(1390,377,'共 42 首',12,'muted',anchor='end');s.line(264,393,332,393,'accent',3)
artistSongs=[('凌晨一点半','林屿 · 陈澈','网易云','04:36'),('把日子折成信','林屿','网易云','03:48'),('没有寄出的明信片','林屿','网易云','04:12'),('街灯亮起的时候','林屿','网易云','03:52'),('下一站是海边','林屿 · 南岸','网易云','05:04')]
rows(s,264,442,1128,artistSongs,playing=0);s.button(1188,786,92,'上一页');s.button(1292,786,100,'下一页');s.text(264,812,'第 1 页',12,'muted');s.save('04-desktop-artist.svg')

s=SVG(title='零拍桌面 · 用户主页与公开歌单');sidebar(s,'发现');player(s)
s.text(264,123,'用户主页',14,'muted');s.avatar(264,162,136,'南',1);s.text(432,187,'用户 · 网易云',12,'muted');s.text(432,237,'南岸',36,weight=600,font=DISP);s.text(432,275,'收藏生活里的微小声音。',14,'muted');s.text(432,307,'从评论作者进入',11,'muted')
s.text(264,377,'公开歌单',17,'accent',600);s.text(388,377,'播客节目',17,'muted');s.line(264,393,332,393,'accent',3)
for i,(t,num) in enumerate([('晚间散步','36 首'),('周末没有安排','24 首'),('窗边的半小时','18 首'),('写给路上的人','52 首')]):
  x=264+i*286;s.cover(x,426,240,i);s.text(x,704,t,18,weight=500);s.text(x,734,num+' · 网易云歌单',12,'muted');s.icon('chevron',x+218,690,19)
s.text(264,811,'仅显示对外公开的内容',12,'muted');s.text(1392,811,'第 1 页  ›',12,'muted',anchor='end');s.save('05-desktop-user.svg')

s=SVG(title='零拍桌面 · 热门电台与节目列表');sidebar(s,'播客 / 电台');player(s,'把今天留给自己','南岸 · 夜行电台',True)
s.text(264,126,'播客 / 电台',26,weight=600);s.text(264,158,'从一个声音，遇见另一种生活。',13,'muted');s.pill(264,183,'热门电台',98,True);s.button(695,178,162,'打开电台链接',icon='external')
radios=[('夜行电台','南岸','日常、城市与一些小小的心事。'),('窗边放映室','阿遥','聊电影，也聊电影以外。'),('耳边的山海','山间邮局','在声音里去远一点的地方。'),('不赶时间','陈澈','每周一封，写给忙碌的你。')]
for i,(t,a,d) in enumerate(radios):
  y=238+i*138
  if i==0:s.rect(252,y-12,618,126,'surface',12,'line');s.rect(252,y+8,3,84,'accent',1)
  s.cover(270,y,96,i);s.text(386,y+24,t,19,weight=600);s.text(386,y+52,a,12,'muted');s.text(386,y+82,d,12,'muted');s.icon('chevron',827,y+35,20)
s.text(264,814,'第 1 页',12,'muted');s.text(851,814,'下一页  ›',12,'accent',anchor='end')
s.line(908,178,908,813);s.cover(944,190,96,0);s.text(1060,219,'夜行电台',22,weight=600,font=DISP);s.text(1060,249,'主播  南岸  ›',12,'muted');s.text(1060,276,'42 期节目',12,'muted');s.text(944,336,'全部节目',16,weight=600);s.text(1390,336,'最新在前',11,'muted',anchor='end')
for i,(t,date,d) in enumerate([('把今天留给自己','11 月 16 日','38:24'),('你最近一次认真散步是什么时候','11 月 09 日','42:10'),('房间，也是一座小小的岛','11 月 02 日','31:48'),('忙碌的日子，慢一点说话','10 月 26 日','36:06')]):
  yy=362+i*104;s.text(946,yy+23,t,14,'accent' if i==0 else 'text',500);s.text(946,yy+51,date+' · '+d,11,'muted');s.text(946,yy+79,'正在播放' if i==0 else '播放',11,'accent');s.text(1030,yy+79,'下一首播放',11,'muted');s.icon('more',1370,yy+57,19);s.line(944,yy+96,1392,yy+96)
s.save('06-desktop-radio.svg')

# Four Android screens at their actual 390 x 844 logical design size.
def phone_start(s,x,title):
  s.rect(x,82,390,844,'canvas',24,'line');s.text(x+24,113,'9:41',12,weight=600);s.text(x+366,113,'5G  ▰',11,'text',anchor='end');s.text(x+24,163,title,24,weight=600)
def phone_bottom(s,x,active=0,mini=True):
  if mini:
    s.rect(x,790,390,64,'surfaceMuted');s.cover(x+16,800,44,0);s.text(x+72,819,'凌晨一点半',13,weight=600);s.text(x+72,839,'林屿 · 陈澈',11,'muted');s.icon('pause',x+290,810,24);s.icon('list',x+343,812,22);s.rect(x,790,174,2,'accent')
  s.rect(x,854,390,72,'surface',0);s.line(x,854,x+390,854)
  for i,(n,ico) in enumerate([('曲库','library'),('发现','compass'),('我的','user')]):
    cx=x+65+i*130
    if i==active:s.rect(cx-28,861,56,30,'accentSoft',15)
    s.icon(ico,cx-10,866,20,'accent' if i==active else 'muted');s.text(cx,913,n,11,'accent' if i==active else 'muted',500,'middle')
  s.rect(x+143,920,104,3,'text',2)

s=SVG(1736,1000,'零拍 Android · 曲库、播放、评论与播客流程');s.rect(0,0,1736,1000,'#E7DFE3');s.text(40,40,'ANDROID · 390 × 844 dp',12,'muted',font=MONO);s.text(1696,40,'设计预览 · 所有内容为虚构示例',12,'muted',anchor='end')
xs=[40,462,884,1306]
x=xs[0];phone_start(s,x,'曲库');s.icon('search',x+342,140,24);s.pill(x+24,190,'歌单',68,True);s.pill(x+104,190,'歌曲',68);s.pill(x+184,190,'本地',68);s.cover(x+24,245,144,0);s.cover(x+222,245,144,1);s.text(x+24,417,'夜行电台',16,weight=500);s.text(x+222,417,'慢下来',16,weight=500);s.text(x+24,441,'36 首 · 混合歌单',11,'muted');s.text(x+222,441,'24 首 · 混合歌单',11,'muted');s.text(x+24,497,'最近添加',18,weight=600);s.text(x+366,497,'查看全部',11,'accent',anchor='end')
for i,(t,a,_,d) in enumerate(SONGS[:3]):
  y=519+i*80;s.cover(x+24,y,52,i);s.text(x+91,y+23,t,14,weight=500);s.text(x+91,y+46,a,11,'muted');s.icon('more',x+340,y+17,22)
phone_bottom(s,x)

x=xs[1];phone_start(s,x,'');s.icon('down',x+24,140,24);s.text(x+195,158,'正在播放',14,'muted',500,'middle');s.icon('more',x+342,140,24);s.cover(x+48,206,294,0);s.text(x+24,548,'凌晨一点半',28,weight=600,font=DISP);s.text(x+24,583,'林屿 · 陈澈',14,'muted');s.icon('chevron',x+140,566,18);s.icon('heart',x+340,548,24);s.text(x+195,631,'让夜晚轻轻经过',18,'accent',anchor='middle',font=DISP);s.rect(x+24,672,342,3,'line',2);s.rect(x+24,672,137,3,'accent',2);s.circle(x+161,673,5,'accent');s.text(x+24,700,'01:42',11,'muted',font=MONO);s.text(x+366,700,'04:36',11,'muted',anchor='end',font=MONO);s.icon('repeat',x+29,735,24);s.icon('previous',x+95,731,28);s.circle(x+195,746,32,'accent');s.icon('pause',x+180,731,30,'surface');s.icon('next',x+267,731,28);s.icon('list',x+337,735,24);s.line(x+24,808,x+366,808)
for dx,t,ico in [(24,'歌词','music'),(144,'评论','chat'),(264,'相似歌曲','compass')]:s.icon(ico,x+dx+13,833,22);s.text(x+dx+24,883,t,12,'muted',anchor='middle')
s.rect(x+143,920,104,3,'text',2)

x=xs[2];phone_start(s,x,'');s.icon('back',x+24,141,24);s.text(x+195,158,'评论',18,weight=600,anchor='middle');s.text(x+24,205,'凌晨一点半',16,weight=600);s.text(x+24,232,'林屿 · 陈澈',12,'muted');s.pill(x+24,256,'评论',104,True);s.pill(x+140,256,'相似歌曲',104);s.text(x+24,326,'评论',14,weight=600);s.text(x+366,326,'只读',12,'muted',anchor='end')
for i,(name,l1,l2) in enumerate([('晚归的人','这一句听了好多次，今晚终于','可以慢慢走回家。'),('纸飞机','耳机里的雨声很轻，刚刚好。','谢谢这首歌。'),('小岛来信','把今天没做完的事先放下，','明天再继续。')]):
  y=350+i*137;s.avatar(x+24,y,36,name[0],i);s.text(x+72,y+15,name,13,weight=500);s.icon('chevron',x+72+len(name)*13+5,y,14);s.text(x+72,y+35,'11 月 16 日 · 赞 32',10,'muted');s.text(x+72,y+66,l1,13);s.text(x+72,y+91,l2,13);s.line(x+72,y+113,x+366,y+113)
s.text(x+24,783,'仅浏览评论 · 第 1 页',11,'muted');s.text(x+366,783,'下一页  ›',11,'accent',anchor='end');phone_bottom(s,x,1)

x=xs[3];phone_start(s,x,'');s.icon('back',x+24,141,24);s.text(x+195,158,'夜行电台',18,weight=600,anchor='middle');s.icon('more',x+342,141,24);s.cover(x+24,194,104,0);s.text(x+148,222,'夜行电台',22,weight=600,font=DISP);s.text(x+148,253,'主播  南岸  ›',13,'muted');s.text(x+148,281,'42 期节目',12,'muted');s.text(x+24,335,'日常、城市与一些小小的心事。',13,'muted');s.text(x+24,386,'全部节目',18,weight=600);s.text(x+366,386,'最新在前',11,'muted',anchor='end')
for i,(t,d) in enumerate([('把今天留给自己','38:24'),('认真散步的那一天','42:10'),('房间，也是一座小岛','31:48')]):
  y=410+i*116;s.text(x+24,y+22,t,15,weight=500);s.text(x+24,y+49,'11 月 '+str(16-i*7)+' 日 · '+d,11,'muted');s.button(x+24,y+65,86,'播放',i==0,icon='play',h=34);s.text(x+127,y+88,'下一首播放',12,'muted');s.icon('more',x+340,y+72,22);s.line(x+24,y+110,x+366,y+110)
phone_bottom(s,x,1);s.text(40,970,'曲库 → 迷你播放条 → 正在播放 → 评论 / 相似歌曲',13,'muted');s.text(1696,970,'发现 → 热门电台 → 电台详情 → 播放节目',13,'muted',anchor='end');s.save('07-android-flows.svg')

s=SVG(1440,1100,'零拍 · 关键状态与双端交互');s.rect(0,0,1440,1100,'canvas');s.text(40,56,'每一步，都有下一步',28,weight=600);s.text(40,86,'关键状态与交互 · 静态设计说明 · 虚构示例',13,'muted')
# Settings: account state sync is distinct from ordinary library synchronization.
s.rect(40,122,650,354,'surface',12,'line');s.text(64,159,'设置 / 同步',18,weight=600);s.text(64,197,'歌单与歌曲注释',14,weight=500);s.text(64,224,'已连接同步仓库 · 最近同步 14:32',12,'muted');s.button(534,183,132,'立即同步',icon='sync');s.line(64,248,666,248);s.text(64,281,'同步登录状态',15,weight=500);s.rect(610,262,52,28,'line',14);s.circle(624,276,10,'surface');s.text(64,311,'已关闭 · 不上传或导入登录状态',12,'muted');s.text(64,345,'开启后，将加密同步各音源的登录状态。',12,'muted');s.text(64,370,'每台设备都需要单独开启，并设置相同口令。',12,'muted');s.text(64,410,'关闭登录态同步时，歌单同步无需解锁。',12,'muted');s.text(64,449,'关闭不会删除远端已有记录。',12,'muted')
s.rect(714,122,686,354,'surface',12,'line');s.text(738,159,'当前播放的作者',18,weight=600);s.text(738,191,'凌晨一点半',12,'muted')
for i,(name,txt) in enumerate([('林屿','歌手 · 网易云'),('陈澈','歌手 · 网易云')]):
  y=212+i*74
  if i==0:s.rect(735,y-3,644,68,'none',11,'focus',2)
  s.avatar(750,y+8,40,name[0],i);s.text(808,y+26,name,14,weight=500);s.text(808,y+49,txt,11,'muted');s.icon('chevron',1344,y+19,20)
s.text(738,395,'点击作者进入主页 · Esc 关闭',12,'muted',font=MONO);s.text(738,431,'仅一位作者时直接进入主页。',12,'muted');s.text(738,455,'节目显示主播；电台本身不算作者。',12,'muted')
# Three operational states with explicit recovery.
for x,title in [(40,'加载中'),(502,'空歌单'),(964,'主页加载失败')]:s.rect(x,504,436,244,'surface',12,'line');s.text(x+24,542,title,17,weight=600)
for i in range(3):
  s.rect(64,564+i*48,34,34,'surfaceMuted',6);s.rect(112,567+i*48,290-(i%2)*70,10,'surfaceMuted',4);s.rect(112,585+i*48,150,8,'surfaceMuted',4)
s.text(526,588,'还没有歌曲',16,weight=500);s.text(526,619,'搜索一首，或粘贴歌曲 / 视频链接。',12,'muted');s.button(526,659,132,'添加歌曲',True,'plus')
s.text(988,585,'B 站暂时限制了访问',16,weight=500);s.text(988,616,'平台暂时限制访问，请稍后重试。',12,'muted');s.button(988,658,100,'重试',True);s.button(1100,658,124,'返回')
# Restriction and shortcut handling are presented as interaction annotations.
s.rect(40,776,650,274,'surface',12,'line');s.text(64,814,'添加节目到歌单',18,weight=600);s.text(64,850,'「把今天留给自己」',14);s.rect(64,875,602,64,'surfaceMuted',8);s.text(80,901,'节目不能添加到网易云歌曲歌单。',13,'text');s.text(80,924,'请选择本地歌单或混合歌单。',12,'muted');s.button(64,968,170,'选择本地歌单',True);s.button(246,968,100,'取消')
s.rect(714,776,686,274,'surface',12,'line');s.text(738,814,'双端分别设计 · 桌面常用快捷键',18,weight=600)
for i,(key,t) in enumerate([('Space','播放 / 暂停'),('Ctrl/⌘ F','聚焦搜索'),('+ / −','调节音量'),('u','查看当前作者；也可直接点击作者名')]):
  y=846+i*37;s.rect(738,y,96,28,'surfaceMuted',6);s.text(786,y+20,key,11,'muted',500,'middle',font=MONO);s.text(850,y+20,t,12)
s.text(738,1029,'手机独立触控导航与底部面板；桌面不要求全键盘操作。',11,'muted');s.save('08-states-and-interaction.svg')


s=SVG(1314,1000,'零拍 Android · 发现电台与作者选择');s.rect(0,0,1314,1000,'#E7DFE3');s.text(40,40,'ANDROID · 发现与作者入口',12,'muted');s.text(1274,40,'设计预览 · 虚构示例内容',12,'muted',anchor='end')
x=40;phone_start(s,x,'发现');s.icon('search',x+342,140,24);s.pill(x+24,190,'网易云',88,True);s.pill(x+124,190,'B 站',70);s.text(x+24,267,'热门电台',20,weight=600);s.text(x+366,267,'查看全部',12,'accent',anchor='end')
for i,(t,a,d) in enumerate(radios[:4]):
  y=294+i*118;s.cover(x+24,y,80,i);s.text(x+122,y+25,t,17,weight=600);s.text(x+122,y+51,a,12,'muted');s.text(x+122,y+76,d[:14],11,'muted');s.icon('chevron',x+346,y+28,20)
phone_bottom(s,x,1)

x=462;phone_start(s,x,'');s.icon('down',x+24,140,24);s.text(x+195,158,'正在播放',14,'muted',500,'middle');s.cover(x+48,206,294,0);s.text(x+24,548,'凌晨一点半',28,weight=600,font=DISP);s.text(x+24,583,'林屿 · 陈澈',14,'muted');s.icon('chevron',x+140,566,18)
s.raw(f'<rect x="{x}" y="82" width="390" height="844" rx="24" fill="#2B262B" fill-opacity="0.24"/>');s.rect(x,550,390,376,'surface',24);s.rect(x+173,561,44,4,'line',2);s.text(x+24,606,'当前播放的作者',21,weight=600);s.text(x+24,636,'凌晨一点半',12,'muted')
for i,(name,letter) in enumerate([('林屿','林'),('陈澈','陈')]):
  y=657+i*90;s.avatar(x+24,y,48,letter,i);s.text(x+88,y+23,name,16,weight=500);s.text(x+88,y+46,'歌手 · 网易云',12,'muted');s.icon('chevron',x+342,y+16,20)
s.line(x+24,830,x+366,830);s.text(x+195,878,'取消',14,'muted',anchor='middle');s.rect(x+143,920,104,3,'text',2)

x=884;phone_start(s,x,'');s.icon('back',x+24,140,24);s.text(x+195,158,'歌手主页',18,weight=600,anchor='middle');s.avatar(x+24,198,80,'林');s.text(x+126,227,'林屿',28,weight=600,font=DISP);s.text(x+126,257,'歌手 · 网易云',12,'muted');s.text(x+24,318,'唱一些日常，记录沿途的声音。',13,'muted');s.text(x+24,368,'热门作品',18,weight=600);s.text(x+366,368,'42 首',12,'muted',anchor='end')
for i,(t,a,_,d) in enumerate(artistSongs[:4]):
  y=400+i*86;s.text(x+24,y+24,f'{i+1:02}',11,'muted',font=MONO);s.text(x+62,y+24,t,14,weight=500);s.text(x+62,y+49,a+' · '+d,11,'muted');s.icon('more',x+342,y+20,20);s.line(x+62,y+70,x+366,y+70)
s.text(x+24,778,'第 1 页',11,'muted');s.text(x+366,778,'下一页  ›',11,'accent',anchor='end');phone_bottom(s,x,1)
s.text(40,970,'发现 → 热门电台 → 电台详情',13,'muted');s.text(1274,970,'点击当前歌曲作者 → 多人选择 / 单人直接进入主页',13,'muted',anchor='end');s.save('09-android-discovery-authors.svg')
print('Generated 9 editable SVG boards and tokens.json')
