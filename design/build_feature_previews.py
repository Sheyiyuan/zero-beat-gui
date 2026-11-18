#!/usr/bin/env python3
"""Complete feature boards plus four theme references; never runtime screenshots."""
from pathlib import Path
from build_previews import SVG, C, sidebar, player

root=Path(__file__).resolve().parent

def panel(s,x,y,w,title,rows):
    s.rect(x,y,w,280,'surface',12,'line');s.text(x+24,y+38,title,21,weight=600)
    for i,(label,value) in enumerate(rows):
        yy=y+78+i*46;s.text(x+24,yy,label,14);s.text(x+w-24,yy,value,13,'accent',anchor='end');s.line(x+24,yy+17,x+w-24,yy+17)

s=SVG(title='零拍 · 设置、账号与下载');sidebar(s,'下载');player(s)
s.text(264,114,'你的音乐工作区',30,weight=600)
panel(s,264,146,548,'外观与窗口',[('配色','零拍红 / 寒拍蓝'),('主题','跟随系统'),('关闭窗口','后台播放'),('快捷键','自定义 · GUI 独立保存')])
panel(s,836,146,564,'账号',[('哔哩哔哩','已登录 · 管理'),('网易云音乐','扫码登录 →'),('二维码过期','刷新二维码'),('登录失效','保留歌单，重新登录解冻')])
s.rect(264,450,1136,340,'surface',12,'line');s.text(288,491,'下载管理',22,weight=600);s.text(1376,490,'同时两首 · 后台任务',12,'muted',anchor='end')
for i,(title,state,action) in enumerate([('凌晨一点半','6.8 / 12 MB','取消'),('山间来信','等待下载','取消'),('晚风经过站台','已完成 · 含歌名、歌手、专辑','导出 / 分享'),('回到岸边','下载未完成','重试 / 续传')]):
 y=524+i*58;s.text(288,y,title,15);s.text(650,y,state,13,'muted');s.button(1180,y-27,192,action,h=40)
s.save('10-desktop-settings-downloads.svg')

s=SVG(1440,960,'零拍 · 片段与歌词编辑');sidebar(s);player(s)
s.text(264,115,'凌晨一点半 · 片段编辑',28,weight=600)
s.rect(264,151,1136,328,'surface',12,'line');s.text(288,191,'完整时间轴',16,weight=600)
s.rect(300,245,1060,8,'line',4);s.rect(510,245,610,8,'accent',4)
for x,label in [(300,'00:00'),(510,'00:52'),(1120,'03:18'),(1360,'04:36')]:s.text(x,284,label,13,'muted',anchor='middle')
for x in [510,1120]:s.circle(x,249,10,'accent')
s.button(288,334,216,'起点  00:52.000');s.button(520,334,216,'终点  03:18.000');s.button(754,334,150,'试听',True)
s.text(288,410,'试听使用当前播放／暂停意图；取消恢复原片段。',14,'muted');s.button(1100,409,120,'取消');s.button(1236,409,140,'保存片段',True)
panel(s,264,505,548,'歌词来源',[('自动来源','优先平台歌词'),('平台 / LRCLIB','搜索 → 预览 → 绑定'),('本地文件 / 本机曲目','仅本设备'),('绑定失效','自动回退，保留绑定')])
panel(s,836,505,564,'浏览歌词',[('当前行','高亮 + 翻译'),('跟随播放','手动滚动暂停跟随'),('点击歌词行','跳转到对应时间'),('来源偏移','− 0.5 秒 / 归零 / + 0.5 秒')])
s.save('11-desktop-lyrics-clip.svg')

s=SVG(title='零拍 · 同步与冲突');sidebar(s);player(s)
s.text(264,115,'同步你的曲库',28,weight=600)
panel(s,264,151,548,'仓库连接',[('地址','SSH / HTTPS'),('登录态同步','默认关闭'),('自动同步','由本设备选择'),('访问令牌 / 口令','仅本机保存')])
panel(s,836,151,564,'后台操作',[('测试连接','可取消'),('同步中','页面关闭不重复启动'),('出现冲突','逐项比较'),('归档歌单','查看删除前的副本')])
s.rect(264,455,1136,337,'surface',12,'line');s.text(288,497,'夜行电台 · 比较版本',22,weight=600)
s.text(288,539,'本地',16,'accent',600);s.text(860,539,'远端',16,'accent',600);s.line(828,520,828,694)
for i,(a,b) in enumerate([('36 首 · 最近一次手动整理','38 首 · 另一台设备更新'),('排除：晚风经过站台','新增：山间来信、回到岸边'),('保留本机文件夹引用','仅同步可迁移数据')]):
 s.text(288,581+i*36,a,14);s.text(860,581+i*36,b,14)
s.button(288,716,160,'保留本地',True);s.button(464,716,160,'使用远端');s.button(640,716,160,'保留两者');s.text(1376,742,'已选方案保留，处理完再应用',12,'muted',anchor='end')
s.save('12-desktop-sync.svg')

s=SVG(1440,1010,'零拍 Android · 授权、下载与账号');s.rect(0,0,1440,1010,'canvas');s.text(40,48,'手机使用完整页面、底部操作面板与系统文件选择器',24,weight=600)
for i,(title,rows) in enumerate([
 ('文件夹歌单',[('选择文件夹','系统授权'),('扫描本层音乐','128 / 251'),('中途取消','保留原索引'),('授权失效','重新授权'),('移除歌单','文件保留')]),
 ('下载与导出',[('下载完成','私人目录'),('保存到系统音乐','含歌曲标签'),('另存为 / 分享','系统面板'),('导出失败','原下载保留'),('失败任务','重试 / 续传')]),
 ('账号与主题',[('B 站 / 网易云','扫码登录'),('二维码过期','点击刷新'),('取消登录','停止轮询'),('外观','系统 / 深 / 浅'),('配色','红 / 蓝 / 自定义')])]):
 x=40+i*464;s.rect(x,90,432,844,'surface',24,'line');s.text(x+24,145,'‹  '+title,23,weight=600)
 for j,(label,value) in enumerate(rows):
  y=214+j*108;s.text(x+24,y,label,18,weight=500);s.text(x+24,y+34,value,14,'muted');s.line(x+24,y+64,x+408,y+64)
 s.rect(x,770,432,78,'surfaceMuted');s.text(x+24,804,'凌晨一点半',15,weight=600);s.text(x+24,830,'林屿 · 陈澈',12,'muted');s.icon('pause',x+330,797,24);s.icon('next',x+380,797,24)
 for j,label in enumerate(['曲库','发现','我的']):s.text(x+72+144*j,894,label,16,'accent' if j==2 else 'muted',anchor='middle')
s.text(40,979,'设计对照 · 虚构示例 · 设备验收以 Flutter 实际界面为准',13,'muted');s.save('13-android-files-downloads-accounts.svg')

palettes={
 'red-light':{},
 'blue-light':{'accent':'#245C9E','accentSoft':'#DCE9FA','canvas':'#F2F6FC','surfaceMuted':'#E9EFF8','focus':'#245C9E'},
 'red-dark':{'canvas':'#191418','surface':'#241E23','surfaceMuted':'#30272D','text':'#F4E9EF','muted':'#CCBBC4','line':'#53424C','accent':'#FFB0C6','accentSoft':'#5C243A','focus':'#FFB0C6','danger':'#FFB4AB','warning':'#FFCB80'},
 'blue-dark':{'canvas':'#121921','surface':'#1B242E','surfaceMuted':'#26313E','text':'#E8EFF8','muted':'#B8C6D7','line':'#405266','accent':'#A8CAFF','accentSoft':'#1F426D','focus':'#A8CAFF','danger':'#FFB4AB','warning':'#FFCB80'},
}
import re
for theme,overrides in palettes.items():
 target=root/'themes'/theme;target.mkdir(parents=True,exist_ok=True)
 # One substitution pass avoids replacing newly inserted colors a second time.
 replacements={C[key]:value for key,value in overrides.items()}
 pattern=re.compile('|'.join(map(re.escape,replacements))) if replacements else None
 for file in (root/'screens').glob('*.svg'):
  text=file.read_text()
  if pattern:text=pattern.sub(lambda match:replacements[match.group()],text)
  (target/file.name).write_text(text)
print('Generated 13 boards in four theme references')
