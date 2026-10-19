# TribeHunt 项目规则

## 已验证的项目事实

- 引擎：Godot 4.7.2；`project.godot` 的 `config/features` 为 Godot 4.x Forward Plus。
- 主要语言：GDScript（项目中主要逻辑文件为 `.gd`）；回归测试启动脚本使用 PowerShell（`.ps1`）。
- 项目入口：`project.godot` 配置的主场景为 `res://scenes/menu/main_menu.tscn`；README 记录使用 Godot 4.7.2 打开 `project.godot` 并按 F5 运行。
- 代码：`scripts/` 中的游戏逻辑与服务脚本，以及 `addons/godot_mcp/` 中的 Godot MCP 插件代码。
- 场景与配置资源：`scenes/` 保存 `.tscn` 场景；`data/` 保存项目数据资源；`feature_profiles/`、`script_templates/` 保存项目已有的配置/模板内容。
- 素材：`assets/`、`参考图/`、`美术初稿/` 及项目中使用的图片等美术资源。不要把素材扫描当作代码调查的默认步骤。
- 测试：`tests/regression.tscn` 与 `tests/regression.gd` 定义回归检查；真实存在且文档化的命令是：
  `./tests/run_regression.ps1 -GodotPath "<Godot 控制台程序绝对路径>"`
  脚本以 Godot headless 模式运行回归场景，并检查日志中的错误和 `REGRESSION: ... checks, 0 failures`。
- 生成文件/缓存：`.godot/`、各类 `.import`/`.uid` 文件，以及 `tmp/` 中的测试数据和日志属于导入、派生或运行时生成内容；除非任务直接涉及，不把它们当作手写源代码调查入口。
- 构建/输出：`output/` 与 `export_templates/` 是项目中实际存在的输出或导出相关目录；只有任务涉及构建/导出时才调查其内容。不要把构建产物当作源代码修改目标。

## 调查与执行规则

- 先判断任务是设计/分析、Bug 排查还是实现。分析与解释只读不改文件；实现任务才修改必要文件并执行匹配风险的验证。
- 按任务范围读取：先看入口、直接相关场景/脚本、错误信息和直接依赖；证据不足或涉及跨模块调用、生命周期、资源加载、状态同步、架构或回归风险时，再逐步扩大范围。
- 复杂 Bug 不得为了节省上下文而省略关键依赖、调用链、生命周期分析或必要测试。
- 不重复读取未变化的文件，不重复执行无新依据的搜索/测试/命令；不扫描无关素材、缓存、生成文件、依赖目录或构建产物。
- 不凭猜测改代码；关键事实不确定时先查证。不要把互不相关的问题草率合并。
- 只报告与结论有关的问题、证据、根因、方案/改动、验证和风险，不复制大量项目文档或通用编程教程。

## 现有项目规则

涉及 Godot 架构、命名、阶段范围、存档、联机、进度和交接文档时，先阅读并遵守 [`.cursor/rules/godot-project.mdc`](.cursor/rules/godot-project.mdc)。该文件包含更详细且已有的项目约束；本文件不重复复制其全文。
