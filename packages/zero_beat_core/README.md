# zero_beat_core Dart 数据契约

当前 core 的 **显式投影 DTO**、Dart 不可变模型与 JSON 编解码器。覆盖曲目、歌单、搜索、播放状态、歌词、评论、相关推荐、主页、播客电台、下载和同步摘要；无需 Flutter 或第三方 Dart 依赖。版本为 `0.8.0-dev.1`，不发布到 pub.dev。

类型、JSON 编解码与契约测试位于本包；本机 RPC、FFI 启动与重连位于相邻 `zero_beat_rpc` 包，Flutter 播放引擎位于 `app/lib/engine`。类型验证不能代替真实平台验收。

## 在 Flutter 中引用

GUI 应用的 `pubspec.yaml`（应用放在 `app/` 时）：

```yaml
dependencies:
  zero_beat_core:
    path: ../packages/zero_beat_core
```

```dart
import 'package:zero_beat_core/zero_beat_core.dart';

final page = CommentPage.fromJson(payload);
final canBrowse = source.capabilities.names.contains(SourceCapability.browse);
final author = page.comments.first.authorRef; // 未知作者为 null
```

`SourceID` / `BrowseKind` 等是开放字符串值对象。`isKnown` 可判断当前契约是否认识该值；新音源或枚举值可被读取、保留并写回，不会导致整页解析失败。调用 core 前仍需检查音源能力。

## 单一来源与更新

`tool/core-bindings/wire/types.go` 是 wire 字段的唯一来源；`project.go` 逐字段投影**真实 core 类型**。生成器从 Go DTO 生成 Dart 类型，从 core 常量生成枚举/能力名，从真实 core 数据生成 fixture。`schema.json` 同时记录 core 结构体的字段指纹；core 新增或改字段会使 `-check` 失败，必须明确决定是否投影。

在 GUI 仓库根目录（集成仓库已在 `go.work` 注册生成工具）：

```sh
go test ./tool/core-bindings/...
go vet ./tool/core-bindings/...
go run ./tool/core-bindings/cmd/generate
# CI/审查：不修改文件，发现生成结果或 core 字段漂移则失败
go run ./tool/core-bindings/cmd/generate -check
```

生成器使用 `dart format` 固定代码样式。Dart 不在 PATH 时设置 `DART=/absolute/path/to/dart` 或传 `-dart`。生成器要求 Dart SDK 3.11+；格式校验使用开发环境中的 Dart 3.11.0。独立检出 GUI 时，请在父目录创建包含本地 core 与 `tool/core-bindings` 的 Go workspace；不依赖尚未发布的 core v0.8.0 下载，也不在 `go.mod` 写本地 replace。

Dart 验证在本包目录执行：

```sh
dart pub get --offline
dart analyze
dart run test/contract_test.dart
dart format --output=none --set-exit-if-changed lib test
```

目前 55 个 Go 生成 fixture、103 项 Dart 契约检查。Go 测试另验证实际 core 投影、单位、64 位边界、nullable、未来枚举、凭据隔离和入参转换。无网络 API 请求或用户数据访问。

## 类型与单位

| core / 数据 | Dart wire 约定 |
| --- | --- |
| `store.Song`, `source.Track` | 独立 DTO；`Song.remoteId` 兼容旧 BVID；`Track.externalId` 保持源引用 |
| 平台 ID / 节目 ID / `CID` | ID 保留字符串；数值型 int64 ID 使用十进制 JSON 字符串 → Dart `BigInt` |
| 播放量、点赞、下载字节数 | 十进制 JSON 字符串 → `BigInt`；不通过 double |
| 秒制曲长 / `time.Duration` | `duration_ms`、`position_ms` 等毫秒整数，只转换一次 |
| 绝对时间 | UTC RFC3339，固定毫秒精度；零时间或未知时间为 null |
| 未知 enum | 保留原字符串；core 新数值枚举为 `unknown:N` |
| 能力位 | 当前已知名称列表 + 未知位 `unknown_bits`，后者为 `BigInt` |
| slice/map | 投影输出空 `[]` / `{}`；模型复制并冻结容器，不接受 null |
| `BrowseEntry` | `ref` 与 `track` 恰好一个非 null；集合和可播放节目不混淆 |
| `PlaybackSnapshot.requestId` | 当前控制器请求号；不等于 RPC id 或引擎 `playback_id` |
| `sync_accounts` | 默认为关闭，独立于普通曲库同步和自动同步 |

网易云节目保留 `program:ID`；例如 `netease:program:2066770638:1` 不改写成底层歌曲 ID。歌曲引用 page 在投影时规范为至少 1；歌词候选的 page 仍保持 core 原值（不适用时为 0）。

Dart 解码器严格拒绝缺失必填字段、类型错误、非整数/超安全范围毫秒、非有限浮点、越界 int64 和无效日期；未知字段忽略。`BigInt` 的 int64 范围及毫秒的 JSON 安全整数范围也在编码时检查。公开构造函数不替代业务入参校验，不能直接把模型当写操作命令。

## Go 接入边界

RPC handler 从 core 读取后使用投影及验证编码：

```go
payload, err := wire.Marshal(wire.FromComments(corePage))
```

`wire.Marshal` 在序列化前检查时间、精度和集合/曲目的互斥约束，避免错误 wire 数据跨边界。`TrackRef.Core()`、`BrowseRef.Core()`、`Quality.Core()`、`PlaybackMode.Core()` 和 `Clip.Core()` 提供少量可复用的反向转换，拒绝非法值与当前 core 不支持的枚举；音源 registry/capability、权限、取消和写操作验证仍由 Session 负责。存储 DTO 没有“直接反写数据库”的入口。

## 凭据与引擎类型

通常只导入 `zero_beat_core.dart`。公开类型不含 session cookie、账号 payload、token、密钥或口令；同步地址去掉 userinfo/query/fragment。同步、搜索、下载、歌词、扫描的原始错误不跨界，只投影 `has_error` / `has_warning` / `warning_count`；后续 Session 应按错误类别产生可展示消息。

`StreamInfo` 只含编码、时长、音质、到期时间和片段。真正引擎需要的 URL/Headers 只由独立入口导出：

```dart
import 'package:zero_beat_core/engine_contract.dart';
```

`EngineStream` 用于经过认证的引擎桥，不能进入页面状态、日志或持久化。分离导出用于防止误用，并非沙箱或安全隔离机制。二维码登录的 key/URL 也是临时数据；由账号页面与 Session 管理刷新、取消和过期，不写入日志或偏好。

## 有意不做自动投影的 core 状态

数据库句柄、Registry/Source 实例、账号 session、同步密钥、内部预取、洗牌基队列、重试预算和落盘时钟均留在 Go。同步冲突事务、鉴权二维码、RPC 方法信封与错误类别使用独立业务契约，不用 Go 反射整包暴露给 Dart。新增 DTO 应加入生成 allowlist、core 字段指纹、真实 core fixture 和必要的边界测试。
