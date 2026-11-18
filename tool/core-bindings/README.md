# Go → Dart 契约工具

生成与当前 core 对齐的 GUI 数据类型。使用根集成仓库的 Go workspace 引用本地 core。生成器留在本目录，导入 `github.com/sheyiyuan/zero-beat-gui/wire`；DTO 在 GUI 模块根的 `wire` 包。

- `../../wire/types.go`：显式 wire DTO。
- `../../wire/project.go`：真实 core → wire 投影，不反射暴露业务对象。
- `../../wire/input.go`：少量已校验的反向引用/枚举/片段转换。
- `../../wire/validate.go`：序列化前检查精度、时间和模型约束。
- `../../wire/schema.go`：公开 DTO allowlist 和 core 常量映射。
- `../../wire/fixtures.go`：从真实 core 类型构造跨语言 fixture，记录 core 字段指纹。
- `cmd/generate`：生成 Dart、fixture 和 schema；`-check` 检测漂移。

执行与边界说明见 [Dart 包文档](../../packages/zero_beat_core/README.md)。生成器需 Dart 3.11+，Go 测试本身无需 Dart 或网络。
