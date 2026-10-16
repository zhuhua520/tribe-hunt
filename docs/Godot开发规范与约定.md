# Godot 开发规范与约定

> 项目：TribeHunt / 部落远征
> 引擎：Godot 4.7.2
> 脚本：GDScript
> 目的：将 Godot 官方文档中的建议转为本项目可执行的约定。Godot 不强制唯一的目录架构；本文件里的结构是团队约定，不是引擎硬性要求。
> Cursor 会自动应用的强约束规则位于项目根目录的 .cursor/rules/godot-project.mdc。

## 1. 基本原则

1. 以场景和节点组织可运行的游戏对象；让每个场景有清楚的职责。
2. 节点负责行为、生命周期和与场景树交互；Resource 负责可复用的静态配置数据。
3. 用信号表达事件，用明确引用或参数传递依赖。只有确实跨场景、跨生命周期的服务才考虑 Autoload。
4. 单人、本地合作、在线合作共享玩法数据模型，但输入、房间管理和网络传输分别处理。
5. 先实现能验证玩法的最小数据结构，不为了未定内容搭建过度通用的框架。

## 2. 推荐目录与命名

现有项目的 scenes、scripts、data、assets、docs 目录可继续使用；随着系统增长，优先按功能归档资源和场景：

	project.godot
	scenes/
	  menu/
	  combat/
	  player/
	  enemies/
	  weapons/
	  ui/
	scripts/
	  combat/
	  player/
	  weapons/
	  progression/
	  networking/
	  save/
	  ui/
	data/
	  weapons/
	  modules/
	  constellations/
	  waves/
	assets/
	  sprites/
	  audio/
	  fonts/
	docs/

Godot 官方建议使用 snake_case 作为目录和文件名，降低大小写敏感文件系统及导出后的路径问题。项目约定如下：

| 对象 | 命名方式 | 示例 |
| --- | --- | --- |
| 文件、目录、脚本文件 | snake_case | weapon_data.gd、main_menu.tscn |
| GDScript 全局类和节点名称 | PascalCase | WeaponData、Player、MainMenu |
| 函数、变量、信号 | snake_case | load_profile、health_changed |
| 常量 | CONSTANT_CASE | MAX_PLAYERS |
| 枚举类型 | PascalCase；成员 CONSTANT_CASE | enum Rarity { COMMON, EPIC } |

新增功能尽量贴近所属场景或玩法系统；通用资源只有被多个功能确实共享时才上移。所有项目路径用 Godot 的 res:// 资源路径，不写死 Windows 绝对路径。

### 2.1 GDScript 格式与代码顺序

- 使用 UTF-8 无 BOM、LF 换行，并在文件末尾保留换行。
- 缩进使用 Godot 编辑器默认的 Tab；避免同一文件混用 Tab 和空格。
- 类和函数之间留出空行；长表达式换行时保持续行缩进清楚；一行只表达一个主要动作。
- 信号使用 snake_case，优先表达已发生的事件，例如 player_spawned、wave_completed。
- 按以下顺序组织脚本，便于快速找到接口和状态：
  1. 注解、class_name、extends、类说明；
  2. signals、enums、constants；
  3. @export 属性、公开变量、私有变量、@onready 引用；
  4. Godot 生命周期回调；
  5. 公开方法、私有方法、内部类。
- 在跨系统接口、存档结构、网络消息、配置数据和容易混淆的数值上明确类型；类型明显时可用类型推断。函数参数和返回值尽量有类型标注。
- 私有变量和私有函数以单个下划线开头；不要为了形式给每个局部变量都增加类型噪声。

## 3. 场景、节点与脚本边界

- 一个场景代表一个可独立实例化、可理解的对象或流程，例如 Player、Enemy、Weapon、MainMenu、Expedition。
- 节点树使用 PascalCase 节点名；子节点只暴露调用方真正需要的接口，不让外部脚本依赖内部树的任意路径。
- 尽量让单个脚本承担单一职责。波次管理、玩家输入、武器攻击、掉落、界面显示和存档分别由对应组件或系统承担。
- 可复用玩法对象优先封装成场景；纯逻辑且无需节点生命周期的计算不必强制做成 Node。
- 用信号通知状态变化，例如波次结束、玩家倒下、投票结果、存档完成；避免脚本互相查询深层节点树。
- 对必需节点引用在初始化时明确获取并校验；不要每帧用字符串路径反复查找节点。
- 当前原型通过 player 分组获取唯一玩家；加入本地/在线合作前，应改成明确的玩家集合或玩家 ID 映射，不允许其他系统默认永远只有一个玩家。

## 4. Resource 与可变运行时状态

Godot Resource 是数据容器，适用于项目内可复用的静态设计数据；加载过的 Resource 会被缓存并共享。不要把玩家运行时可变状态直接写回共享的设计 Resource。

### 4.1 静态设计数据

适合用自定义 Resource 保存并以 .tres 编辑：

- 武器定义：稳定 ID、显示名、类别、攻击方式、品质/稀有度字段、适配标签。
- 模块定义：稳定 ID、类别、初始星级、元素值、武器标签、词条占位。
- 星座定义：稳定 ID、星点列表、套装门槛/完整收集奖励占位。
- 波次、敌人、掉落和远征规则配置。

设计资源尽量保持数据声明，不在其中保存某一局的临时叠层、已装备状态或玩家强化结果。配置需要变化时新增明确数据版本或迁移逻辑。

### 4.2 可变运行时数据

玩家拥有的实例、当前强化等级、已发现星点、远征中的临时增益和队伍状态由运行时状态对象管理。实例通过稳定 ID 引用静态定义，不直接改写共享资源。远征结束时，由结算系统明确筛选哪些数据写入玩家存档。

波次配置目前已使用 Resource 文件，这是可沿用的数据驱动方式。未来不要把“有配置文件”误当成“规则必须完全通用化”；只抽象已验证的共同变化点。

## 5. Autoload 使用约定

Autoload 是在项目运行期间挂到根场景的节点，不应被当成放任何全局变量的地方。仅当服务需要跨场景持续存在、拥有自身生命周期并被多个系统使用时才考虑 Autoload。

可能适合成为 Autoload 的服务：

- SaveService：负责读写玩家设置和进度。
- SessionService：负责当前单人/本地/在线会话的创建和退出。
- SettingsService：当多个界面都要共享音量和输入配置时。

不建议作为 Autoload 的对象：

- 当前关卡中的玩家、敌人、波次管理器、投射物和 HUD；
- 只在一个场景使用的菜单或战斗界面；
- 只为方便调用而设置的杂项方法或任意游戏状态。

在加入 Autoload 前，先考虑场景所有者传引用、信号或 Resource 数据是否已经足够。避免通过 Autoload 形成隐式依赖和无法追踪的全局状态。

## 6. 输入和本地多人

- 玩法输入通过 InputMap 命名动作，不在角色脚本里把按键写死。
- 动作名使用 snake_case，例如 move_left、move_right、attack、auto_attack_toggle、interact、vote_extract、vote_continue、pause。
- 键盘、手柄和重绑定都映射到同一类动作接口。
- 本地多人要将每位玩家的输入设备与玩家 ID 绑定；不允许所有玩家都读取同一份全局输入状态。
- 菜单操作和战斗操作分开映射，暂停/投票由会话规则决定响应玩家或全队。
- 输入动作清单随原型变化更新；最终控制方案未定前，不把动作名和键位视为定案。

## 7. 联机结构与状态权威

联机功能分为房间发现、网络会话、游戏状态同步三层：

1. **房间发现**：好友邀请、创建大厅、公开房间搜索和加入。
2. **传输/会话**：建立连接、玩家身份、连接状态、断开与重连。
3. **游戏同步**：玩家输入、移动、敌人、波次、伤害、掉落、投票和结算。

Godot MultiplayerAPI/RPC 可作为同步起点；Steam 大厅负责找人和组队，不自动等同于战斗状态同步。网络后端、Steam 扩展和传输协议等联机原型后再选。

项目联机基线建议：

- 采用房主权威原型：房主验证玩家请求并决定波次、敌人、伤害、掉落、撤离投票及奖励结果。
- 客户端发送输入或意图，不直接声明“我造成了多少伤害”或“我获得了什么”。
- RPC 仅接收必要参数；服务器校验发送者、范围、当前状态和调用频率。
- RPC 双方对应节点路径和名称保持一致；多人创建的节点应有稳定的命名和生命周期规则。
- 同步稳定 ID、简单数值和明确的数据结构，不直接发送任意节点对象或整个 Resource 图。
- 将玩家输入和游戏结果分开，使离线单人、同机合作和在线合作可共用战斗规则。
- 在出现真实性能需求前，不提前引入复杂预测、回滚或自研可靠传输系统。

房主权威不是防作弊的完整保证；上线前必须结合平台服务和实际威胁范围重新检查。

## 8. 存档与设置

Godot 的 user:// 是适合导出游戏写入用户数据的位置；res:// 作为游戏资源目录使用，不把运行时存档写回项目资源目录。

### 8.1 数据分层

- 设置数据：音量、显示、语言和输入映射，可独立保存。
- 进度数据：已解锁项目、星点发现状态、收藏和构筑预设。只在玩法规则确认后启用对应字段。
- 远征临时数据：本局状态默认不进入永久进度；中途续局另行设计。
- 联机数据：服务器结算后只向各玩家保存其应得的本地进度，归属规则另行确认。

### 8.2 存档格式与可靠性约定

- 顶层包含 schema_version、更新时间和各类稳定数据。
- 用稳定内容 ID 关联定义，不保存节点路径、内存对象引用或仅供显示的本地化字符串。
- 读取时校验字段类型和合法范围；缺字段时提供合理默认值，未知字段可忽略。
- 数据结构升级时编写从旧版本到新版本的迁移步骤，并保留原始备份直到迁移成功。
- 重要写入先落到临时文件，确认写入成功后再替换主文件；保留上一份备份，避免断电或进程中止造成唯一存档损坏。
- 在设置变更、远征安全结算点和永久解锁后保存；避免每帧或每次微小状态变化都写盘。
- 明确“新游戏”“删除进度”“重置设置”是不同操作，并在界面确认危险操作。
- 首版暂不承诺 Steam Cloud、多存档槽、加密或防篡改。

具体采用 ConfigFile、JSON、自定义 Resource 或其他格式，应以字段稳定性、迁移能力和调试便利性决定；不能只因格式方便就把任意对象序列化进存档。

## 9. Steam Workshop 与外部内容

- Workshop 入口、订阅 API、内容下载器和内容加载器保持松耦合。
- 先确定内容包清单格式、稳定 ID、游戏版本兼容、资源路径和校验规则，再开始正式上传/订阅功能。
- 外部内容不得覆盖游戏内置文件或任意写入用户目录之外的位置。
- 首版优先考虑受控的数据和资源格式。未明确沙箱与审核方案前，不执行创作者提供的任意 GDScript。
- 加载外部内容失败时应可禁用或移除该内容并回到正常主菜单，不让坏内容破坏本地存档。

## 10. 版本控制与资源修改

- 提交 project.godot、场景、脚本、.tres 配置、源资产和项目文档。
- 编辑器生成的 .godot 缓存由 .gitignore 忽略，不作为手工编辑或提交内容。
- 使用 Godot 编辑器的 FileSystem 面板移动/重命名资源，避免资源引用路径失效。
- 资源路径大小写保持一致；目标平台可能区分大小写。
- 先保存小而完整的功能改动，避免一次提交同时改变输入、存档格式、网络状态和资源结构。
- 插件统一放在 addons/，并记录来源、版本和启用范围。

## 11. 建议的代码检查清单

提交一个功能前，开发者自查：

- 场景和脚本职责是否单一，是否引入不必要的全局状态？
- 项目数据 Resource 是否被运行时直接改写？
- 新增状态是否有稳定 ID、所有者和生命周期？
- 是否仍能在单人、本地多人和在线会话中复用相同规则？
- RPC 是否校验调用者和输入，是否同步了不必要的对象？
- 存档是否有版本号、默认值和失败恢复路径？
- 新增文件名、节点名、脚本名和信号是否符合本约定？
- 设置、主菜单、Workshop 占位和游戏状态是否各自落在合适的场景中？

## 12. 官方参考

以下参考以项目当前 Godot 4.7 系列为准；官方文档中的目录布局是建议，不是强制架构。

- [Godot 最佳实践](https://docs.godotengine.org/en/4.7/tutorials/best_practices/)
- [Godot 项目组织与命名建议](https://docs.godotengine.org/en/4.7/tutorials/best_practices/project_organization.html)
- [GDScript 风格指南](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [Godot Resource](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)
- [GDScript 静态类型](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html)
- [Autoload 与普通节点](https://docs.godotengine.org/en/4.7/tutorials/best_practices/autoloads_versus_regular_nodes.html)
- [Godot 数据偏好与结构选择](https://docs.godotengine.org/en/4.7/tutorials/best_practices/data_preferences.html)
- [Godot 文件系统与 user:// 路径](https://docs.godotengine.org/en/4.7/tutorials/scripting/filesystem.html)
- [Godot 高层多人游戏 API](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html)
- [Godot 输入示例与 InputMap](https://docs.godotengine.org/en/4.7/tutorials/inputs/input_examples.html)
- [Steamworks 大厅与匹配](https://partner.steamgames.com/doc/features/multiplayer/matchmaking)
- [Steamworks 创意工坊](https://partner.steamgames.com/doc/features/workshop)

## 13. 适用范围与更新

本文件规范项目代码、场景、数据和内容加载的实现方式；它不替代《部落远征-完整设计方案-v2.md》中的玩法决策。若玩法方案改变，应同步审视数据结构和网络/存档边界。若 Godot 大版本升级，应重新检查官方文档和项目约定。
