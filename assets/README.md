# assets

只放美术与音频。玩法数值请放 `res://data/` 或脚本 `@export`。

## 替换约定
- 保持文件路径与文件名不变，直接覆盖文件即可。
- 当前玩家占位图：`sprites/player/player.png`
- 后续敌人 / 武器 / 弹体请分别放入对应子目录。

## 导入说明
Godot 首次打开工程时会生成 `.import` 与 `.godot/imported/`。若编辑器外新增图片后运行报错找不到 Texture2D，用编辑器打开一次，或执行：

```text
Godot_v4.7.2-stable_win64_console.exe --path <本工程> --headless --import --quit-after 2
```
