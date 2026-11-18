# GUI 完整功能验收

更新：2026-11-18。本轮交付目标为 Linux 与 Android；core／TUI 0.8.0 不发布。表中的“已接入”表示核心和页面存在，不表示所有业务及设备场景已验收。macOS、Windows 的应用构建与设备验收留到后续。

## 功能、入口与证据

| 功能 | 核心接口／页面 | 实现状态 | 自动验证 | 设备验证 |
| --- | --- | --- | --- | --- |
| 自绘窗口、托盘、迷你、第二实例 | Linux runner、DesktopWindow、WindowFrame | Linux 启动即无系统装饰，默认后台，无托盘时最小化；独立保存普通／迷你尺寸 | Linux 构建、实际窗口启动；多屏位置函数、窄窗与主题回归通过 | 拖动／缩放、多屏热插拔、托盘桌面环境矩阵待人工验证 |
| 账号二维码／本机网页登录／取消／退出 | auth.*、AccountsBody、LoginOptions、WebLoginPage、QRLoginBody | 手机优先打开网易云／哔哩哔哩官方页面并在本机完成登录；桌面仍以二维码为主。会话经账号接口校验后写入既有账号存储，校验失败会恢复原会话 | 登录选项顺序、cookie 白名单、拒绝未知字段、校验失败回滚有自动测试 | 真机官方页面登录、系统 WebView 缺失和自然过期待验证 |
| 歌单创建／编辑／导入 | library.*、LibraryTools、混合引用编辑器 | 本地／仅本机／混合、重命名／删除、镜像解锁、导入／每日推荐、刷新已接入 | 核心曲库回归通过 | 真实平台导入和同源云端加歌待验证 |
| 排除／批量／整歌单 | library.batch*、LibraryPane、SongSelectionScope | 稳定 ID，多选／选择全部，核心取得完整目标；部分失败保留并可重试 | 251 首目标、跨页多选、取消请求后任务保留、只重试失败项、旧目标隔离通过 | 超大真实歌单操作待验证 |
| 搜索与内容链接 | search.*、source.open_link、SearchBox／LocalSearchBody | 当前歌单／本地全部、单源／合并、分页、部分失败；链接按类型打开 | 搜索分页与失败重试、旧搜索回包、桌面返回曲库通过 | 在线分 P／主页链接联合操作待验证 |
| 播放与队列 | player.*、Transport／QueuePanel | 四模式、队列排序／删除／清空、音质／静音／补偿、本地优先、睡眠与预取；Android 响度均衡尚不可用 | 完整 core race、旧代次／慢加载／唯一播放器／暂停 seek／焦点拒绝通过；预取复用、加载期间睡眠、停止保留队列／显式重启 race 通过 | Linux WAV 解码、位置推进、PulseAudio、MPRIS 暂停；Android SAF WAV 实际出声获用户确认、暂停／恢复及短时后台通过；在线音质、长时锁屏待验证 |
| 片段 | player.clip.*、ClipEditor | 全时轴、起止输入、整曲试听、保存／清除／取消，固定曲目 | 取消恢复原片段及最新暂停意图、A→B→A 旧编辑 token 拒绝的 race 回归通过；GUI 用例通过 | 待验证 |
| 歌词 | lyrics.*、LyricsBody／绑定流程 | 自动／翻译、当前行／跟随／手动、行跳转、平台／LRCLIB／本地文件／本机曲目绑定、预览／解绑／偏移 | 核心歌词／绑定、SAF 同名／标签匹配、坏旁挂回退、独立翻译回归通过；Linux 真实绑定／偏移／解绑通过 | Android 同名旁挂原文／中文翻译、暂停时点行跳转仍暂停通过；手动文件绑定、内嵌歌词、外部平台失效回退待验证 |
| 评论／发现／作者／电台 | content.*／browse.*、ContentBody／BrowseBody | 只读、作者选择、公开主页／歌单／电台／节目，保留 program 身份 | core／TUI 内容与节目回归通过；页面目标与独立导航栈通过 | 在线长内容／评论作者连续浏览待验证 |
| 文件夹歌单 | library.folder*／resource.*、系统选择器／扫描对话框 | 桌面可取消扫描、Android SAF 浅层扫描／持久授权／缺失保留／重新授权；URI 身份保留，ContentResolver 内容暂存为私有可 seek 文件 | 身份复用、目录缺失、旧扫描隔离、提交回滚、不可读保留索引、取消／授权回收通过；4 项 JVM 缓存测试通过 | Android 授权测试目录扫描 2 首 WAV、覆盖安装／冷启动后直接读取通过；权限撤销、目录移动、大文件与空间不足待验证 |
| 下载管理 | download.*／tasks.*、DownloadsBody／TasksBody | 单曲／批量／完整歌单、双并发、取消／续传、失败重试、补全／移除／删除／分享／定位 | 取消后单写者、关闭回收、资源变化续传拒绝、实际桌面封装通过 | 网络中断、磁盘不足、Android 离线播放待设备验证 |
| Android 原生封装／导出 | zero_remux.c、ContentResolver／MediaStore | libav 音频包复制、歌名／艺人／专辑、输出回读后原子落盘；音乐目录／指定位置导出 | 官方签名／固定摘要；同一 C 源码 Linux 原生执行 AAC/MP3/FLAC/Opus 标签与包哈希、取消、损坏输入通过；APK 7 库 ABI／16KB 通过 | Android 真机执行封装、标签回读及导出失败待验证 |
| 同步 | sync.*、SyncBody／冲突比较／归档 | 初始化／加入、SSH／HTTPS／令牌、测试连接、手动／自动、选择冲突／放弃、口令／忘记密钥；登录态每设备默认关闭 | core sync 全量 race（v2／v3、排除、仅本机保护、重复同步）通过 | 隔离数据 TUI／GUI go-git 互通（排除、仅本机保留、文件夹不上传、默认关闭登录态、再次同步无额外提交）通过；真实远端和多设备冲突待验证 |
| 主题与快捷键 | settings.gui.*、SettingsBody | 红蓝深浅／系统／自定义颜色，GUI 快捷键独立保存，保护文本输入 | 配色、快捷键覆盖、文本焦点、长标题语义、大字体／横屏／窄桌面通过 | TalkBack 连续操作、减弱动画系统设置待验证 |
| 连接与生命周期 | NativeCore／CoreRuntime／Session | 启动一次、手动重连、断线停止、不重放写命令；Android 私有 Unix socket；关闭屏障等待启动回收，任务归运行时持有 | 真 libzero TCP／Unix 启动／握手／重连／关闭重启；Go 连接清理、Flutter 连接界面通过 | Linux 真播放器重连保持停止；Android 选择器／短时后台返回无需重连通过；活动重建待验证 |

## 本轮检查结果

- core、GUI、TUI 的完整 `go test -race ./...` 通过；任务并发／关闭改动后的 Session race 复验通过。三个模块 `go vet ./...` 通过；本次最新代码再次通过。
- Dart RPC 13 项通过，包含显式启用的真实动态库测试；类型契约 103 项检查、55 份 Go 样本，生成漂移检查通过。
- Flutter 42 项通过（含搜索／内容跨页多选、双击与按钮、独立移动返回栈、200 首分页、焦点和大字体／窄窗）。本次新增断线全屏页、片段 A→B→A、Android 扫描取消及损坏旁挂四项用例已执行；Flutter 共 46 项通过。
- Android 真机修复后的最新检查：Flutter 分析、49 项回归；Dart RPC 分析、15 项回归（含显式启用的真动态库 TCP／Unix）；Android 私有缓存 4 项 JVM 测试；Session／RPC／runtime race、Session／GUI vet 均通过。TUI／GUI 互通专项本次未重复运行。
- Linux debug bundle 构建通过；真实 media_kit／Go／MPRIS 联合用例通过。新手势与自绘窗口 Tooltip 等故障由真实运行发现并修复。
- Android arm64 debug APK 构建通过，最终包中 7 个动态库的 AArch64、依赖闭包、ELF LOAD 及 ZIP 16KB 对齐通过。最新同步幂等修复后的正常 Linux bundle 与 arm64 APK 已重建。
- 已连接 Xiaomi 17 Pro（Android 16、arm64、4KB 页），完成安装、冷启动、目录扫描、授权读取、实际出声及旁挂翻译歌词。修复选择器后台断线（Unix socket）和原始 SAF 描述符访问不兼容（私有缓存）；短时后台与媒体控制的证据和边界见[Android 真机验收](18-android-device-validation.md)。
- 最新代码三个 module 在 `GOWORK=off` 临时代理下的独立编译、测试编译和 vet 通过；本次没有在隔离 module 中执行测试；core sync/session race 已在最新同步修复后通过。
- Linux／darwin／Windows／Android arm64 的 core 依赖边界和构建通过；Go→Dart 生成漂移检查与 103 项类型契约再次通过。
- 最新应用、测试、Linux 联合用例、TUI／GUI 互通用例及 RPC 包 Dart 分析通过。Android 真机已开始验收，尚未闭环；Linux／Android 应用已按最新通信修复代码重建。

## 验收产物与命令

应用路径与命令见[运行说明](../app/README.md)和[构建说明](06-build-release.md)。本地日志位于 `build/validation/logs/`，Linux 真实界面截图和 PulseAudio 输出证据位于 `build/validation/evidence/`。这两个目录为本地验证产物，不属于源代码发布。

设计稿为十三张画板与四套主题，可在[预览索引](../design/index.html)切换。设计稿不计为真实界面验收。

## 未闭环项目

Android 设备已可用，但真机验收和真实平台账号流程尚未闭环，不能声明“全部功能验收完成”。当前 Android 播放库没有 `loudnorm`／`alimiter`，自动响度均衡不计为完成。除表中设备项外，还要补足真实磁盘不足、Android 授权撤销／恢复、30 分钟后台锁屏、通知触控、耳机／焦点竞争、原生下载标签与导出，并完成 Linux 托盘／拖动／缩放与多屏人工操作。最终交付须保持 Linux 与 APK 和源码一致，不创建标签或正式发布。

## 本次续做变更

- Android 目录查询接入 `CancellationSignal`，取消后关闭扫描页面；目录扫描与播放文件描述符使用独立执行队列。读完当前文件后的清理在后台完成。
- SAF 歌词保留 `lyrics/`、同名／元数据标签匹配、`.trans.lrc`／`.zh.lrc` 翻译及内嵌回退，解析复用 Go 的编码规则。
- 扫描提交在一个事务里写根目录、索引和歌词；模拟末尾写入失败验证全部回滚。取消的新授权、被替换／移除且无人引用的旧授权均释放。
- 片段编辑增加核心 token 与界面失效标记，切歌后旧编辑不能复活；取消试听恢复原片段并保持最新暂停意图。
- 账号页监听状态事件；全局断线遮罩覆盖根播放器页面；运行时关闭等待启动／重连完成清理，允许之后再次启动。
- Android SAF 读取转为私有可 seek 缓存，句柄关闭删除文件，进程重启回收遗留文件；Activity 不提前关闭后台播放句柄。
- 补齐 `player.stop` 和 Android 系统媒体停止；释放焦点、关闭前台播放状态、保留队列位置，只有显式播放才重新加载。
