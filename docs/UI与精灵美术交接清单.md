# UI 与精灵美术交接清单

> 更新日期：2026-10-16  
> 用途：给后续视觉替换用的挂点说明。当前资源都是可运行占位，不是最终美术。  
> 本轮只整理路径、节点和替换约束。最终立绘、背景、图标和皮肤仍等待 Codex 后续制作。

窗口基准是 1280×720。战斗是俯视角 2D。竞技场 `Arena` 开启 `y_sort_enabled`，角色原点参与前后排序。界面在 `CanvasLayer`（战斗 HUD 层为 10）上，不跟角色一起排序。

替换贴图时保持文件路径不变，只换图像内容。不要改碰撞形状、武器伤害或撤离流程。当前精灵都是单帧，场景里没有 `SpriteFrames` 或 `AnimationPlayer`。后续若加动画，先保持 1 帧静止图可用。

## 1. 现有精灵

| 用途 | 路径 | 现有尺寸 | 挂接 | 锚点与变换 | 使用场景 | 后续 |
| --- | --- | --- | --- | --- | --- | --- |
| 玩家 | `assets/sprites/player/player.png` | 32×32 | `scenes/combat/player.tscn` 的 `Sprite2D`；联机占位 `scenes/combat/net_player.tscn` 同路径 | 精灵中心对齐角色原点。碰撞矩形 28×28，也在原点 | 单人竞技场、联机测试场 | 做俯视单帧。建议仍约 32×32 或 48×48，中心对齐原点。不要改碰撞大小 |
| 普通敌人 | `assets/sprites/enemies/enemy.png` | 28×28 | `scenes/combat/enemy.tscn` 的 `Sprite2D`；`scenes/combat/net_enemy.tscn` 同路径 | 精灵中心对齐原点。碰撞矩形 26×26 | 三波普通敌人、联机测试敌人 | 做俯视单帧，约 32×32，中心对齐。此文件不要拿去当野猪王 |
| 野猪王身体 | 当前仍引用 `assets/sprites/enemies/enemy.png` | 源图 28×28，场景放大 2.4 | `scenes/combat/boar_king.tscn` 的 `BodySprite` | 角色原点是地面锚点。精灵位置 `(0, -78)`，缩放 `(2.4, 2.4)`。碰撞圆在原点，半径 36 | 第三波后的野猪王 | 以后单独做 `assets/sprites/enemies/boar_king.png`，只改 `BodySprite` 的纹理、位置和缩放。脚底对齐原点上方，身体向上延伸，不要盖住地面预警和玩家。建议画布约 96×128，脚在画布底边中点；接入时把偏移改成约 `(0, -半高)`，并去掉现在的 2.4 倍放大。本轮没有新建这个文件 |
| 木棍 | `assets/sprites/weapons/club.png` | 8×24 | `scenes/weapons/melee_weapon.tscn` 的 `Sprite2D` | 位置 `(18, 0)`，绕武器原点旋转 | 玩家近战 | 单帧，握点靠近原点。建议约 16×32 |
| 弹弓 | `assets/sprites/weapons/sling.png` | 16×16 | `scenes/weapons/ranged_weapon.tscn` 的 `Sprite2D` | 位置 `(-16, 8)` | 玩家远程 | 单帧。建议约 24×24 |
| 石弹 | `assets/sprites/projectiles/stone.png` | 8×8 | `scenes/weapons/stone_projectile.tscn` 的 `Sprite2D` | 中心对齐弹体。命中圆半径 6 | 弹弓投射物 | 单帧，约 8×8 到 16×16，中心对齐 |

脚本在纹理为空时会再加载上表路径。替换场景里的纹理即可，不必改脚本。

## 2. 野猪王血量与攻击预警

这些不是贴图，本轮不改成图片。

| 用途 | 现在怎么画 | 约束 |
| --- | --- | --- |
| 血量 | `BoarKing/HpLabel`，文字「野猪王 当前/最大」，在身体上方，约 `y = -132` 到 `-106` | 占位文字。以后若做血条，放在身体上方，不要挡住地面圆和冲撞箭头。不要改 `hp` 数值 |
| 脚下占地 | 脚本生成的圆，半径 36，绝对 `z_index = -4` | 对齐地面锚点，画在角色下面 |
| 冲撞预警 | 地面箭头多边形绝对 `z_index = -3`，中线 `z_index = -2`。长约 202，半宽 50 | 必须留在角色和玩家下面，方向要能看清 |
| 震地预警 | 地面圆，半径 118，绝对 `z_index = -3` | 圆要大于身体，玩家要能看出站在圈内还是圈外 |

玩家生命目前只显示在窗口标题，不在 HUD 上。这不阻挡现有按钮流程。以后若加生命文字或血条，放在 `CombatHUD` 的 `CanvasLayer` 上，不要放进角色场景。

## 3. 界面

主菜单已接入饥荒风格手绘背景图 `assets/sprites/ui/main_menu_bg.png`（1280×720），菜单面板与按钮采用无边框、无背景色的纯文字样式（`StyleBoxEmpty`），悬停/聚焦时文字高亮变亮；其余页面仍使用 Godot 默认主题与纯色 `ColorRect` 背景。

| 界面 | 场景或脚本 | 现有结构 | 操作是否齐全 | 后续 |
| --- | --- | --- | --- | --- |
| 主菜单 | `scenes/menu/main_menu.tscn` | `Background`（`TextureRect`，引用 `assets/sprites/ui/main_menu_bg.png`，1280×720）+ 居中透明面板与纯文字无边框按钮（悬停/聚焦文字变亮）。按钮：开始远征（点击后动态加载资源进入部落村落）、在线合作、创意工坊、设置、退出 | 齐全 | 背景图与首页纯文字按钮风格已接入；按钮文字、节点路径和顺序保持不变 |
| 部落村落 | `scenes/village/village.tscn`、`scripts/village/village.gd` | 全几何形状占位：四周方块围成村落边界（未来树木 UI 占位）、村内武器店仅边框占位（无 UI 弹窗）、合成店形状占位、右侧出村道路触发出征选择弹窗（左侧分类占位、右侧目的地出征点接入战斗场景 `Arena`，返回回到村落） | 齐全 | 当前全用几何形状占位，未绘制图片 |
| 模式选择 | `scenes/menu/mode_select.tscn` | 单人（进入部落村落）、本地合作、返回 | 齐全 | 同上 |
| 出征准备/选择 | `scenes/menu/expedition_prep.tscn`，模块勾选由 `scripts/ui/expedition_prep.gd` 生成 | 左侧区域分类占位、右侧具体目的地（出征点）、模块列表、撤离节奏下拉、确认出征（进入 `Arena`）、返回村落 | 齐全 | 勾选框是运行时生成的，场景里没有逐条节点 |
| 战斗 HUD | `scenes/ui/combat_hud.tscn`，层 10 | `StatusLabel`、`BuildStatusLabel`、`ResultPanel`（结果、统计、重新开始、返回主菜单）、`PauseHint` | 齐全 | 结果页要容纳 4 到 5 行统计。不要让角色画到按钮上 |
| 波间构筑 | `scenes/build/build_adjustment_panel.tscn` 只有空的根节点；内容由 `scripts/build/build_adjustment_panel.gd` 在 `_ready` 生成 | 标题、说明、模块勾选、确认构筑并继续 | 齐全 | 以后要换皮时，优先加主题，或再把生成的控件挪进场景。本轮不拆脚本 |
| 撤离选择 | `scenes/ui/extraction_choice_panel.tscn` 同样只有根节点；内容由 `scripts/ui/extraction_choice_panel.gd` 生成 | 继续、撤离 | 齐全 | 同上 |
| 暂停与设置 | `scenes/ui/pause_menu.tscn`、`scenes/ui/settings_panel.tscn` | 继续、设置、结束冒险（回到部落村落）；音量和窗口模式 | 齐全 | 设置仍写入 `user://settings.json`，换皮时不要改存档字段 |
| 结果页 | `CombatHUD/ResultPanel` | 结局标题、用时、击杀、受到伤害；遇到野猪王后多一行遭遇结果 | 齐全 | 面板大约 440×370。五行走得下，不要再缩 |

战斗 HUD、构筑面板和撤离面板都是 `PROCESS_MODE_ALWAYS`。结果出现时会先隐藏后两个面板。换皮时保持这个顺序，避免再次挡住结果按钮。

## 4. 本轮明确不做

- 不新增最终立绘、背景、图标、血条皮肤或动画帧。
- 不把野猪王贴图从 `enemy.png` 拆出去；拆文件留给真正画野猪王的那一次，避免现在复制一张同样的占位图。
- 不改碰撞、伤害、波次、撤离节奏和存档。
