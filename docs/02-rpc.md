# 本机 RPC

Dart 与 Go 在同一个进程里（Windows 为 `zero-core.exe` sidecar），但仍然通过本机 socket 通信。理由：

- 事件推送天然异步，不需要在 FFI 里做回调注册与生命周期管理；
- 同一套协议可以复用到桌面调试、`zero` CLI 验证和 Windows sidecar；
- 序列化边界强制 DTO 稳定，避免把 Go 结构体（无 json tag、含 `time.Time`）直接漏给 UI。

## 传输

- 桌面使用 TCP，绑定 `127.0.0.1:0`，由核心返回实际端口；Windows sidecar 通过 stdout 握手行返回 `{port, token}`；
- Android 使用应用私有目录中的 Unix domain socket，`ZeroStart` 返回 `socket_path` 和 `port: 0`。本机 IPC 不经过 Android 后台 IP 防火墙，避免在系统文件选择器中停留后被断开；socket 权限为 `0600`，关闭时删除，启动时仅回收已无监听者的旧 socket；
- 每行一个 JSON 对象（NDJSON，UTF-8，`\n` 结尾），单行上限 8 MiB；
- 连接建立后第一条必须是 `core.hello`，携带 `token`；校验失败立即断开；
- token 由 `ZeroStart` 返回，只存在内存里，不落盘；桌面端口随机；
- 不接受局域网连接；桌面只监听回环，Android 仅监听应用私有 socket。

## 信封

采用 JSON-RPC 2.0 子集，双向都可用：

```json
{"jsonrpc":"2.0","id":17,"method":"library.playlists","params":{}}
{"jsonrpc":"2.0","id":17,"result":{"playlists":[]}}
{"jsonrpc":"2.0","id":17,"error":{"code":-32010,"message":"曲库暂不可用","data":{}}}
{"jsonrpc":"2.0","method":"player.state","params":{"state":"paused","playback_id":null,"position_ms":0}}
```

- 请求必须有 `id`（正整数，连接内唯一，限制在 JSON 安全整数范围）；Dart 发奇数、Go 发偶数，重连清空 pending 表；通知（无 `id`）只用于事件；
- 结果必须是对象，避免顶层数组/标量；
- 错误码：`-32700` 解析失败、`-32600` 非法请求、`-32601` 未知方法、`-32602` 参数错误、`-32603` 内部错误；业务错误从 `-32000` 起；
- 播放控制带 3 秒超时；auth／content／browse／lyrics／library／search／download／sync／tasks 与链接解析使用 20 秒。长任务立即返回任务 ID。
- `player.play/next/prev` 在会话接受请求后返回 `{request_id}`，不等解析或出声；播放结果走 `player.state`。`download.batch.start` / `sync.action` 返回任务标识，长任务通过事件报告完成。
- 请求处理必须与读循环分离；响应直接完成 pending future。写操作由单一队列发送，不允许两个 writer 拼接帧。

## 命名空间与方向

| 前缀 | 方向 | 用途 |
| --- | --- | --- |
| `core.*` | Dart → Go | 握手与协议控制 |
| `library.*` / `search.*` / `source.*` / `lyrics.*` / `auth.*` / `player.*` / `download.*` / `settings.*` / `sync.*` / `app.*` | Dart → Go | 业务调用；方法名以以下清单为准 |
| `engine.*` | Go → Dart | 音频引擎命令（load/pause/seek/volume/…） |
| 事件（无 id） | 双向 | `player.state`、`engine.position`、`sync.changed`、`download.changed` 等 |

## 握手

`core.hello`：

```json
{"token":"<ZeroStart 返回的随机 token>","api":1,"repo":3,"client_version":"0.1.0","platform":"linux","engine_capabilities":["clip","loudnorm"]}
```

响应：

```json
{
  "api": 1,
  "repo": 3,
  "core_version": "0.8.0",
  "data_dir": "/home/me/.config/zero-beat",
  "capabilities": ["library", "search", "link", "player", "auth", "content", "browse", "lyrics", "settings", "batch", "download", "sync", "tasks", "resource", "clip", "loudnorm"],
  "account": {"bilibili": {"logged_in": true, "name": "..."}, "netease": {"logged_in": false}},
  "player": {"queue_len": 42, "index": 3, "state": "paused", "position_ms": 0, "playback_id": null}
}
```

`api` 不匹配时客户端必须拒绝连接并提示升级；`repo` 用于提示同步格式兼容性。此处按 core 0.8.0 的新仓库 v3 举例；已有 v2 加密仓库仍按核心规则兼容，不能因握手示例而强制升级仓库。GUI 与 core 版本独立，上例展示结构；精确字段以 wire 模型和契约样本为准。

`data_dir` 由启动入口确定，握手不能重定向数据库。引擎能力以本机探测结果为准，下载容器范围需要单独执行平台验收（见 [04-sync-and-data](04-sync-and-data.md)）。

## 已实现方法（api 1）

下表与 `rpc/codes.go`、`rpc/features.go`、`packages/zero_beat_rpc/lib/src/features.dart` 对应。旧的独立 `download.start`、`sync.start`、`player.comp` 等草案名称不作为公共实现声明。

| 功能 | 方法与语义 |
| --- | --- |
| 协议 | `core.hello`、`core.cancel`；页面使用握手缓存，重连才重新握手 |
| 曲库读取 | `library.playlists`、`library.songs`（offset／limit，UI 每批 200） |
| 歌单编辑 | `library.create`、`rename`、`delete`、`unlock`、`refresh`、`refs`、`refs.set`、`remote`、`import_remote` |
| 搜索／链接 | `search.query`、`search.local`、`source.open_link`；保留来源警告、页数及内容类型 |
| 账号 | `auth.accounts`、`auth.qr.start`、`poll`、`cancel`、`auth.logout`；二维码按来源和 key 隔离 |
| 评论／相关推荐 | `content.comments`、`content.related`；只读，绑定进入页面时的曲目 |
| 主页／电台 | `browse.roots`、`profiles`、`page`、`parse`；浏览引用与可播放曲目分开 |
| 歌词 | `lyrics.get`、`candidates`、`preview`、`bind`、`unbind`、`offset` |
| 播放 | `player.play`、`toggle`、`pause`、`stop`、`resume`、`next`、`prev`、`seek`、`volume`、`mode`、`state`；stop 取消加载、释放播放器并保留队列 |
| 队列 | `player.enqueue`、`insert_next`、`queue_remove`、`queue_move`、`queue_clear` |
| 片段 | `player.clip.get`、`player.clip.begin`、`player.clip.edit`（preview／save／clear／cancel，固定目标曲目） |
| 播放偏好 | `settings.get`、`settings.set`，音质／静音／补偿／响度／本地优先／睡眠等 |
| GUI 偏好 | `settings.gui.get`、`settings.gui.set`；主题、配色、窗口和 GUI 快捷键，与 TUI 键位分开 |
| 批量 | `library.batch`（play／enqueue／next）；`library.batch.start`（add／remove）与 `download.batch.start` 返回任务 |
| 下载 | `download.list`、`download.tasks`、`download.add`、`download.action`（cancel／retry／remove_task／cancel_all／remove_record／delete_file） |
| 后台任务 | `tasks.list`、`tasks.cancel`、`tasks.batch_result`、`tasks.retry_batch`、`tasks.folder_result` |
| 桌面文件夹 | `library.folder.start`（add／rescan／replace，后台任务）；`library.folder` 保留同步兼容入口 |
| Android 文件夹 | `library.resource.begin`、`lyrics`、`inspect`、`skip`、`commit`、`cancel`、`unavailable`；暂存扫描、借用描述符、原子提交索引和歌词 |
| 同步 | `sync.status`、`sync.action`（configure／init／probe／now／auto／accounts／token／passphrase／forget／choice／resolve／discard） |
| 冲突与归档 | `sync.conflicts`、`sync.version`、`sync.choices`、`sync.archives`、`sync.archive` |
| 退出 | `app.quit`；释放本运行时成功启动的核心 |

批量选择使用 `playlist_id` 或显式歌曲列表。整歌单由核心取得完整目标，不局限于 UI 当前 200 首；任务固定目标快照，保留成功／跳过／失败结果，重试只处理失败项。云端目标为同来源可写歌单，节目身份 `program:<ID>` 保持不变，禁止写入云端歌曲歌单。

后台任务和下载队列归 Session 所有，Socket 断开后继续存在；页面或连接只订阅并重拉任务状态。未确认写命令不重放。进程关闭取消并回收任务，任务历史不承诺跨进程恢复。`core.cancel` 仅取消当前连接的 RPC；已经接受的后台任务通过 `tasks.cancel` / `download.action` 取消。

### 引擎（Go → Dart）

| 方法 | 说明 |
| --- | --- |
| `engine.load` | `{playback_id, url, headers, codec, duration_ms, quality, clip_start_ms, clip_end_ms, start_at_ms, play_when_ready, volume, comp_db, auto_gain}` |
| `engine.pause` / `engine.resume` / `engine.stop` | 传输控制 |
| `engine.seek` | 绝对位置（ms） |
| `engine.volume` | 0.0–1.0 |
| `engine.comp` | 总增益（dB，含单曲补偿） |
| `engine.auto_gain` | 开关 loudnorm |
| `engine.state` | Go 主动查询；返回 `{playback_id, seq, state, position_ms, duration_ms}`，无已加载流时 playback_id 为 null |

除查询 `engine.state` 外，引擎命令都携带目标 `playback_id`；过期目标返回 `stale_playback`，不得作用于新曲目。尚未加载时音量/增益等只写 Go 缓存，在 load 中一次性传入；`play_when_ready` 来自 session 的播放意图，暂停中的 seek/恢复不能先出声再补 pause。

`engine.load` 在 3 秒内返回 `{accepted:true, playback_id}`，表示已验证参数、安装代次并进入串行执行队列；不代表已缓冲或已出声。打开流的成功/失败通过事件报告，避免把慢网络误判为 RPC 超时。拒绝接受使用 JSON-RPC `error`，不另设 `{ok:false}` 信封。Go 的同步 `PlayAt` 在收到接受响应后返回；真实缓冲状态由后续引擎事件校准。

接受后仍有独立的起播期限：默认 20 秒内必须就绪（playing，或按意图停在已就绪的 paused），否则取消该加载并发送一次 `engine.failed`。5 秒尚未就绪只提示网络较慢；不得因已返回 ack 而无限等待缓冲。期限和时钟在测试中可注入。

### 播放代次、错误与重连

- `playback_id` 是 Go 为每次实际加载分配的不透明字符串，跨核心重启也不复用；同曲重试/重新打开流也要换代次。解析请求号、JSON-RPC `id`、播放代次是三个不同的标识。
- 新点歌在 `BeginPlay` 时立即使旧代次在 Go 侧失效；解析结果用请求号筛选，引擎通知用播放代次筛选。所有引擎事件再带该代次递增的 `seq`，接收方丢弃旧序号；每代只接受一次 `ended` 或 `failed` 终态，之后该代次的普通状态/位置也无效。
- Dart 安装新代次时取消旧加载操作，串行执行 load/seek/stop 等命令；执行前及异步返回后均校验代次，回调必须绑定产生它的操作，不能把迟到回调贴上当前代次。适配器需验证 media_kit 的事件归属；不能可靠区分时，采用停止并隔离旧订阅/重建底层播放器等方案，通过切歌乱序测试后才启用。
- load 拒绝/超时由同步错误路径交给 session；已接受的 load 通过 `engine.failed` 报告失败。同一故障只进入控制器一次；超时后迟到的响应/事件无效。自动重试计数由 session 保留，不因 load 成功清零。
- 暂停、停止、音量等控制命令超时不触发自动重新播放。连接仍可用时查询 `engine.state` 校准；不能确认状态时转入连接恢复。seek 失败需要重新解析时，也必须沿用本次播放的重试预算。
- 断线后 Dart 停止播放、清空旧命令并隔离旧异步回调；Go 失效旧代次、保存最后确认的位置，断线期间不发起自动重试。重连只允许一个引擎所有者，先查询 `engine.state` 确认旧播放已停止，再重拉业务快照；不重放未确认的 next/play 等命令，不自动起播。用户续播时创建新代次。

## 事件

| 事件 | 方向 | 负载 |
| --- | --- | --- |
| `player.state` | Go → Dart | PlayerView：playback_id（未加载时为 null）、play_when_ready、notice／notice_level、snapshot（队列、索引、当前曲目、状态、位置、时长、模式、音量、补偿、片段、睡眠定时） |
| `engine.position` | Dart → Go | `{playback_id, seq, position_ms, duration_ms}`，250ms |
| `engine.state` | Dart → Go | `{playback_id, seq, state: buffering/playing/paused/idle}`；终态只用以下事件 |
| `engine.ended` / `engine.failed` | Dart → Go | `{playback_id, seq, position_ms, error?}`；自然结束/失败，主动 stop 不发送 ended |
| `library.changed` | Go → Dart | 本地/远端歌单变化，UI 重拉 |
| `download.changed` / `tasks.changed` | Go → Dart | 失效通知；读取任务和下载快照 |
| `sync.changed` / `auth.changed` / `settings.changed` / `lyrics.changed` | Go → Dart | 失效通知；重拉对应快照 |
| `all.changed` | Go → Dart | 失效事件合并溢出时，重拉所有业务快照 |
| `notice` | Go → Dart | `{text, level}` |

Linux 第二实例通过 GTK GApplication 激活现有窗口，不发送 `app.activate` RPC。

事件不重放；断线后按上述流程恢复，再拉 `player.state` 与当前列表。传输与 session 消息队列必须有界；只有位置通知可以合并，响应和终态不可静默丢弃，可靠消息无法入队时关闭连接。合并位置时不得越过后续终态的序号顺序。

## DTO 规则

本轮已有可生成的类型契约位于 `tool/core-bindings/wire/` 与 `packages/zero_beat_core/`，详见[绑定说明](../packages/zero_beat_core/README.md)。下列示例用于解释协议；具体已实现的字段与可空性以生成器及契约清单为准。Session 播放代次与 RPC 信封另有明确契约，不能把 controller 的 request 号直接当 playback_id。

- 独立定义 DTO，**不要直接序列化 `store.Song`**：它没有 json tag，`AddedAt` 是 `time.Time`；
- 时间：仅 RPC DTO 的绝对时间用 RFC3339（UTC），时长/位置用毫秒整数；同步仓库保持现有 v2 字段类型与单位，不套用 RPC 规则；
- ID 一律字符串；`source` 用 `"bilibili"` / `"netease"` / `"local"`；
- CID、点赞／播放等 64 位计数以十进制字符串传输，Dart 用精确整数表示；时长与位置仍为毫秒整数，并校验可安全表示范围。不同源的时长先在 Go 投影层转换单位；
- 金额、浮点音量用 `double`，范围在文档里写明；
- 字段只增不改；破坏性变更提升 `api`；
- 错误用 `{code, message, data}`，`message` 给用户看，`data` 给日志。

歌曲 DTO：

```json
{
  "id": "bilibili:BV1xx:1",
  "source": "bilibili",
  "remote_id": "BV1xx",
  "title": "…",
  "artist": "…",
  "album": "…",
  "duration_ms": 245000,
  "cover": "https://…",
  "added_at": "2026-11-01T12:00:00Z"
}
```

播放流 DTO（仅供经过认证的引擎桥接层；页面使用不含 URL／headers 的 StreamInfo）：

```json
{
  "url": "https://…",
  "headers": {"Referer": "https://www.bilibili.com/"},
  "codec": "aac",
  "duration_ms": 245000,
  "quality": "192k",
  "expires_at": "2026-11-01T14:00:00Z",
  "clip_start_ms": 0,
  "clip_end_ms": 0
}
```

## 安全

- 仅监听本机端点；token 随机 128-bit；hello 失败即断开；
- 不把 cookie/Authorization 写进 URL；headers 只在内存与 RPC 帧里；
- 日志脱敏：URL 去掉 query，headers 只留键名；
- 回环地址不是应用隔离边界；桌面随机端口只用于分配。Android 使用私有目录和文件权限隔离，两种传输都必须校验 token；未认证连接不能触发业务、订阅事件或取得引擎所有权。
- hello 必须在连接后 3 秒内完整到达，认证前帧上限 16 KiB、并发未认证连接上限 8；失败即关闭并释放资源。认证后才启用 8 MiB 帧上限与方法分发。
- 每个核心只允许一个已认证的 Dart 控制连接；第二连接被拒绝，重连必须等旧连接注销。token 在核心重启时重新生成，比较采用常数时间实现，不记录到日志。

## 契约测试

现有数据类型使用生成的 core fixture 在 Go / Dart 两端校验；RPC、Session、Flutter 和真实动态库分别验证，结果见[完整验收](17-full-gui-parity.md)，不因 DTO 测试通过而算作设备通过。

- `testdata/rpc/*.json`：每个方法的请求/响应样例，Go 与 Dart 各跑一遍解析；
- 事件顺序测试：起播 → buffering → playing → ended → 下一首；
- 代次测试：快速 A→B、A 的迟到 position/ended/failed、同曲重试、重复终态均不污染 B 或重复切歌；
- 双向调用测试：Go 等待 load ack 时读循环仍可接收响应与事件；队列满不会死锁，可靠消息不静默丢失；
- 超时/断线测试：慢缓冲不误判 load 超时、暂停超时不重播、断线双方停止旧代次、重连不重放命令；
- 取消测试：搜索超时/主动取消释放服务端任务；取消后到达的旧解析结果无效，已提交写操作通过重拉校准；
- 鉴权测试：缺失/错误 token、超时 hello、超大首帧、并发连接超限均被拒绝且无业务副作用；
- 版本测试：`api` 不匹配必须拒绝。


### 首批 Dart 运行时实现

`NativeCore.start` 独占成功启动的原生核心，连接地址和令牌只保存在内存中；`connect` 仅建立 Socket 并握手。运行时断线后先停止旧引擎，再用原凭据手动重连。Go 保留旧控制连接名额直到 Session 完成断线清理，防止旧清理影响新连接。退出及失败回滚调用 `ZeroStop`，不会关闭启动失败时报告的其他实例。

`CoreApi.helloResult` 提供最近一次握手的只读信息，`connections` 发布连接变化；页面不得通过再次 `hello` 查询账号或版本。引擎 `load` 返回表示已接收，实际打开媒体通过事件报告。播放器始终以暂停方式打开文件，随后依据最新意图和音频焦点决定是否出声。

### Android 扫描与片段编辑的补充约定

- `library.resource.begin` 可传 `subdirs`（忽略的音频子目录数）。系统目录枚举只扫描当前层及 `lyrics/` 的歌词文件；不会递归收录音频。
- `library.resource.lyrics` 接收 `key`（扫描 token）、相对 `name` 和借用的 `fd`。Go 限长读取、识别编码；单文件上限 4 MiB、一次扫描歌词总量上限 32 MiB。随后 `inspect` 按音频名、标签及候选优先级选择歌词、合并翻译，坏旁挂继续尝试其他候选及内嵌歌词。
- `commit` 将根目录、文件索引和本机歌词放在一个 SQLite 事务里。全部音频不可读时拒绝覆盖旧索引。`cancel` 丢弃暂存数据；平台层中断目录查询，释放未使用的新授权，共用授权由最后一个歌单释放。
- 新片段编辑器调用 `player.clip.begin` 获得 `{token, clip}`，后续 `edit` 在 `key` 中带回 token。切到别的歌曲再切回后，旧 token 仍无效；试听／取消不改变用户最新的暂停意图。原 `get` 和无 token 的 `edit` 保留兼容性。
