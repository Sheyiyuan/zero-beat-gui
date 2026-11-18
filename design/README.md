# 零拍 GUI 设计预览

这组 SVG 用来评审产品页面与交互，不代替实际 Flutter 截图与交互验收。所有歌曲、人物、评论、歌词、数量与封面均为虚构示例；没有网络图片或在线字体依赖，SVG 文本可直接编辑。

直接打开 [index.html](index.html) 可切换十三张画板以及红／蓝深浅四套主题，支持适应窗口和原尺寸查看。HTML 中的导航可用键盘操作；图内控件是静态效果，不会播放或连接账号。

**桌面与移动端是两套设计。** 共享业务模型与视觉规范，分别设计导航、布局和操作方式。桌面鼠标优先，只提供常用快捷键；Android 触控优先，不显示键位提示。

## 设计方向

延续 TUI 的「佐洛红」品牌，用浅雾玫灰承载长时间浏览，炭黑显示内容，深红只用于主操作、当前播放和焦点。保留 TUI 的列表信息密度，增加封面、作者与内容之间的可见入口；不把曲库做成推荐广告墙。

桌面采用左导航、主内容区、按页面出现的侧栏和常驻播放条。曲目左侧细红线表示当前播放，完整描边表示键盘焦点，两者可以出现在不同歌曲上。手机以曲库、发现、我的为三个主入口，内容浏览期间保留迷你播放条；完整播放页、作者选择底部面板属于临时上层页面。

正文采用 Noto Sans CJK SC；沉浸播放页的歌名、当前歌词少量使用思源宋体（Source Han Serif SC）；时长和快捷键用 DejaVu Sans Mono。字体没有嵌入，缺少字体时使用系统后备。正式应用需确定字体打包与许可证，不应依赖用户安装设计字体。

## 页面与路径

| 画板 | 覆盖内容 |
| --- | --- |
| [01-desktop-library.svg](screens/01-desktop-library.svg) | 混合来源歌单、筛选、列表、独立焦点与播放行、队列、当前作者入口 |
| [02-desktop-playing.svg](screens/02-desktop-playing.svg) | 歌词、当前作者、播放控制、评论与相似歌曲入口 |
| [03-desktop-comments.svg](screens/03-desktop-comments.svg) | B 站预览评论、登录提示、作者主页、相关推荐、播放与入队 |
| [04-desktop-artist.svg](screens/04-desktop-artist.svg) | 歌手信息、热门作品、分页 |
| [05-desktop-user.svg](screens/05-desktop-user.svg) | 用户信息、公开歌单与播客节目分区 |
| [06-desktop-radio.svg](screens/06-desktop-radio.svg) | 热门电台、主播、节目、下一首播放 |
| [07-android-flows.svg](screens/07-android-flows.svg) | 手机曲库 → 播放 → 评论 / 相似歌曲；电台详情 → 节目播放 |
| [09-android-discovery-authors.svg](screens/09-android-discovery-authors.svg) | 手机发现 → 电台；点击当前作者 → 多作者选择 / 单作者主页 |
| [08-states-and-interaction.svg](screens/08-states-and-interaction.svg) | 同步登录状态默认关闭、加载、空歌单、平台失败、节目限制、双端设计与常用快捷键 |

新增 [10-设置与下载](screens/10-desktop-settings-downloads.svg)、[11-歌词与片段](screens/11-desktop-lyrics-clip.svg)、[12-同步冲突](screens/12-desktop-sync.svg)、[13-手机文件／下载／账号](screens/13-android-files-downloads-accounts.svg)。`build_previews.py` 与 `build_feature_previews.py` 生成基础及扩展画板，`themes/` 保存四套主题。

评审时可先看 [桌面主屏 PNG](previews/desktop-library.png)、[手机主流程 PNG](previews/android-flows.png)、[状态页 PNG](previews/states-and-interaction.png)。PNG 只是渲染产物；修改以 SVG / 生成器为准。

## 共用数值

机器可读定义见 [tokens.json](tokens.json)，生成器从同一份 Python 定义生成 token 与全部 SVG，不分别维护多个色板。

| 语义 | 数值 |
| --- | --- |
| 背景 / 表面 / 次级表面 | `#F7F3F5` / `#FFFFFF` / `#F0E8EC` |
| 正文 / 次级文字 / 分隔线 | `#2B262B` / `#6B5F66` / `#DFD4DA` |
| 主色 / 浅选区 / 品牌原色 | `#B02A52` / `#F7DBE2` / `#FF5555` |
| 成功 / 警示 / 失败 | `#1A7F37` / `#8A5A00` / `#B42318` |
| 间距 | 4、8、12、16、24、32、40、48、64；主布局按 8 点网格 |
| 字号 | 11、12、13、14、16、18、20、24、28、32、40 |
| 圆角 | 控件与封面 8；面板 12；手机底部面板 24 |
| 桌面基准 | 1440 × 960；侧栏 224；底部播放条 112；内容边距 40；表行 64 |
| 手机基准 | 390 × 844 dp；左右 24；底导航 72；迷你播放 64 |
| 键盘焦点 | 2 px 深红描边；与控件相隔 3 px |
| 触控 | 所有可操作目标至少 48 × 48 dp；图标、胶囊和小按钮的视觉边界可以更小，实际命中区域必须扩展 |

基准尺寸是设计画布，不是硬编码窗口限制。实现时内容列按剩余宽度伸缩；窄桌面隐藏独立侧栏、把队列移入抽屉；手机加系统安全区域并随大字体自然增高。长标题在列表单行省略，在详情与评论正常换行；2 倍字体、横屏和 320 dp 窄屏须在 Flutter 阶段验收。

## 交互契约

- 非输入区域按 `u`，或点击播放条 / 完整播放页的作者入口，始终查看**当前播放**的作者，和列表选中项无关。单作者直接进入；多作者去重后选择；节目以主播为作者，电台不是作者。请求绑定触发时的曲目，后续切歌不改变已打开的内容。
- 查看选中歌曲的作者放在该歌曲菜单，不给它标 `u`。评论作者通过头像 / 名字入口进入，不另配专用键位。输入框内 `u` 保持正常文字输入。
- 桌面常用快捷键为 Space 播放／暂停、Ctrl/Cmd+F 搜索、+/- 音量、u 当前作者、Esc 关闭弹层。Tab 保留标准焦点行为；不要求每个动作都有映射，不复制 TUI 全套键位。Android 使用独立的底部导航、页面／底部面板和系统返回，主页返回保留列表位置，不留下单作者的空中间页。
- 评论只读，不展示发布、回复或可点击点赞按钮。赞数属于内容信息；B 站匿名预览明确说明登录可查看更多，不伪装完整分页。主页受平台限制时提供重试 / 返回入口，不把登录当作风控解决办法。
- 节目可以加入队列、本地或混合歌单，不能添加到网易云歌曲歌单。保留原节目身份，不把节目当成普通歌曲展示为云端收藏成功。
- **默认关闭的是登录态同步**，不是歌单同步或自动同步。登录态在每设备独立开启；开启后才配置加密口令。关闭时不上传或导入登录状态、不删除远端已有密文、不展示口令配置行或缺失口令警告；新建仓库可无口令同步歌单与注释；已有加密仓库仅在开启登录态同步时需要解锁。
- 加载期间展示占位并保留返回操作；空状态提供明确入口；失败保留已加载内容及重试操作。播放失败不能自动无限重试，恢复与暂停状态按核心规则显示。
- 动效只用于页面切换、播放进度与状态反馈；尊重减少动态效果设置，不能靠动画传达唯一状态。当前 SVG 为静态设计，不包含闪烁骨架动画。

## 更新与检查

修改 [build_previews.py](build_previews.py) 后运行：

```sh
python3 zero-beat-gui/design/build_previews.py
rsvg-convert zero-beat-gui/design/screens/01-desktop-library.svg \
  -o zero-beat-gui/design/previews/desktop-library.png
rsvg-convert zero-beat-gui/design/screens/07-android-flows.svg \
  -o zero-beat-gui/design/previews/android-flows.png
rsvg-convert zero-beat-gui/design/screens/08-states-and-interaction.svg \
  -o zero-beat-gui/design/previews/states-and-interaction.png
```

本次在 Linux 使用系统 Noto Sans CJK SC / 思源宋体和 `rsvg-convert` 渲染，人工检查了桌面曲库、评论、手机主流程、移动端作者流程、状态页，以及其余页面缩略图。检查重点为中文字形、标题 / 按钮溢出、播放条遮挡、焦点可见性、登录态同步措辞、常用快捷键与双端独立导航。所有九张 SVG 均经过 XML 解析和实际栅格化；这些检查不替代 Flutter 布局测试、无障碍测试或真机验收。

当前仅展示浅色主题，封面是几何占位图。设置全页、登录二维码、下载管理、搜索结果、冲突解决、片段编辑、桌面迷你窗口和深色主题仍需在对应实现阶段补齐，不能把这组画板等同于全部 GUI 已设计或可运行。
