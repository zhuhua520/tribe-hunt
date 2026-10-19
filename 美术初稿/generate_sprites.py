# 美术初稿生成器：按参考图风格逐像素绘制草稿精灵
# 用法：python generate_sprites.py
# 产物：本目录下的 player/wolf/boar_king/club/sling/stone/tiger/wolf_king.png 与 preview_sheet.png
import math
import os
from PIL import Image

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

PALETTE = {
    'K': (0x2E, 0x1B, 0x12, 255),  # 深色描边
    'S': (0xE8, 0x87, 0x6C, 255),  # 皮肤
    's': (0xC4, 0x65, 0x4A, 255),  # 皮肤阴影
    'H': (0x3A, 0x2A, 0x1E, 255),  # 头发
    'L': (0xB0, 0x79, 0x4C, 255),  # 皮革亮
    'B': (0x7C, 0x4A, 0x2A, 255),  # 皮革/木头
    'b': (0x54, 0x30, 0x1C, 255),  # 皮革暗
    'W': (0xF2, 0xEA, 0xD8, 255),  # 米白
    'w': (0xD8, 0xCB, 0xB0, 255),  # 米白暗
    'P': (0x5E, 0x6E, 0x7E, 255),  # 裤（灰蓝）
    'p': (0x46, 0x54, 0x5F, 255),  # 裤暗
    'G': (0x8A, 0x85, 0x78, 255),  # 狼灰
    'g': (0x6B, 0x66, 0x59, 255),  # 狼灰暗
    'D': (0x4A, 0x46, 0x3C, 255),  # 狼深色（耳尖/尾尖）
    'E': (0xA0, 0x34, 0x28, 255),  # 敌红眼
    'O': (0xD8, 0x87, 0x3A, 255),  # 虎橙
    'o': (0xA8, 0x64, 0x28, 255),  # 虎橙暗
    'T': (0x3A, 0x2A, 0x1E, 255),  # 虎纹
    'R': (0x6B, 0x4A, 0x30, 255),  # 野猪身体
    'r': (0x4A, 0x30, 0x20, 255),  # 野猪暗
    'M': (0x38, 0x28, 0x1A, 255),  # 野猪鬃毛
    'N': (0x8A, 0x62, 0x42, 255),  # 野猪鼻吻
    'U': (0x9A, 0xA0, 0xA6, 255),  # 石灰
    'u': (0x6E, 0x72, 0x76, 255),  # 石灰暗
    'V': (0xC8, 0xC8, 0xC0, 255),  # 石亮
    'Y': (0xC8, 0x84, 0x2A, 255),  # 琥珀眼
    'Z': (0x56, 0x5A, 0x63, 255),  # 狼王深灰
    'z': (0x3E, 0x42, 0x49, 255),  # 狼王暗
    'Q': (0x8E, 0x93, 0x9C, 255),  # 狼王鬃毛
}


def make_canvas(w, h):
    return [['.' for _ in range(w)] for _ in range(h)]


def rect(grid, x, y, w, h, ch):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= yy < len(grid) and 0 <= xx < len(grid[0]):
                grid[yy][xx] = ch


def px(grid, x, y, ch):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = ch


def ellipse(grid, cx, cy, rx, ry, ch):
    for y in range(cy - ry, cy + ry + 1):
        t = ((y - cy) / ry) ** 2
        if t > 1:
            continue
        dx = int(round(rx * math.sqrt(1 - t)))
        for x in range(cx - dx, cx + dx + 1):
            px(grid, x, y, ch)


def line(grid, x0, y0, x1, y1, ch, thick=1):
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        t = i / steps
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        rect(grid, x - (thick - 1), y - (thick - 1), thick, thick, ch)


def outline(grid):
    w = len(grid[0])
    h = len(grid)
    add = []
    for y in range(h):
        for x in range(w):
            if grid[y][x] != '.':
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and grid[ny][nx] != '.':
                        add.append((x, y))
                        break
                else:
                    continue
                break
    for x, y in add:
        grid[y][x] = 'K'


def shade_bottom(grid, shade_map):
    w = len(grid[0])
    h = len(grid)
    for y in range(h - 2, -1, -1):
        for x in range(w):
            ch = grid[y][x]
            if ch in shade_map and grid[y + 1][x] == 'K':
                grid[y][x] = shade_map[ch]


def to_image(grid):
    h = len(grid)
    w = len(grid[0])
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for y in range(h):
        for x in range(w):
            ch = grid[y][x]
            if ch != '.':
                img.putpixel((x, y), PALETTE[ch])
    return img


def save(grid, name):
    img = to_image(grid)
    img.save(os.path.join(OUT_DIR, name + '.png'))
    return img


def build_player():
    g = make_canvas(32, 32)
    # 头发
    rect(g, 11, 3, 10, 4, 'H')
    rect(g, 10, 6, 1, 5, 'H')
    rect(g, 21, 6, 1, 5, 'H')
    # 羽毛头饰
    px(g, 22, 5, 'w')
    px(g, 22, 4, 'W')
    px(g, 23, 3, 'W')
    # 脸
    rect(g, 11, 8, 10, 4, 'S')
    # 束发带
    rect(g, 10, 7, 12, 1, 'L')
    # 脖子
    rect(g, 14, 12, 4, 1, 's')
    # 皮甲背心
    rect(g, 11, 13, 10, 6, 'B')
    # 手臂
    rect(g, 9, 13, 2, 6, 'S')
    rect(g, 21, 13, 2, 6, 'S')
    # 毛皮领口
    rect(g, 12, 13, 8, 1, 'W')
    # 腰带
    rect(g, 11, 19, 10, 1, 'b')
    # 裤子（两腿）
    rect(g, 12, 20, 3, 5, 'P')
    rect(g, 17, 20, 3, 5, 'P')
    # 靴子
    rect(g, 11, 25, 4, 2, 'b')
    rect(g, 17, 25, 4, 2, 'b')
    outline(g)
    # 眼睛
    px(g, 13, 9, 'K')
    px(g, 18, 9, 'K')
    # 背心阴影与衣襟
    rect(g, 18, 14, 2, 5, 'b')
    rect(g, 15, 14, 1, 5, 'b')
    # 手臂阴影
    rect(g, 10, 14, 1, 5, 's')
    rect(g, 21, 14, 1, 5, 's')
    # 裤子阴影
    rect(g, 18, 21, 1, 3, 'p')
    return g


def build_wolf():
    g = make_canvas(28, 28)
    # 身体
    rect(g, 8, 11, 13, 6, 'G')
    # 头
    rect(g, 4, 8, 6, 7, 'G')
    # 吻部
    rect(g, 1, 10, 4, 3, 'G')
    # 耳朵
    px(g, 5, 6, 'G'); px(g, 6, 7, 'G'); px(g, 5, 7, 'G')
    px(g, 8, 6, 'G'); px(g, 9, 7, 'G'); px(g, 8, 7, 'G')
    # 四条腿
    rect(g, 9, 17, 2, 6, 'G')
    rect(g, 12, 17, 2, 6, 'G')
    rect(g, 16, 17, 2, 6, 'G')
    rect(g, 19, 17, 2, 6, 'G')
    # 尾巴（翘起，逐渐变细）
    rect(g, 20, 10, 3, 2, 'G')
    rect(g, 21, 9, 3, 1, 'G')
    px(g, 23, 8, 'G')
    px(g, 24, 7, 'G')
    outline(g)
    # 鼻子、眼睛
    px(g, 1, 10, 'D')
    px(g, 6, 10, 'E')
    # 腹部与背部阴影
    rect(g, 9, 15, 11, 1, 'g')
    rect(g, 8, 11, 13, 1, 'g')
    # 腿部阴影
    rect(g, 9, 21, 2, 1, 'g')
    rect(g, 12, 21, 2, 1, 'g')
    rect(g, 16, 21, 2, 1, 'g')
    rect(g, 19, 21, 2, 1, 'g')
    # 尾尖
    px(g, 24, 7, 'D')
    return g


def build_boar_king():
    g = make_canvas(96, 128)
    # 身体主体与肩峰
    ellipse(g, 54, 84, 33, 25, 'R')
    ellipse(g, 35, 68, 21, 17, 'R')
    # 头（前下方，与身体相连）
    ellipse(g, 22, 78, 15, 12, 'R')
    # 鼻吻盘
    ellipse(g, 9, 82, 7, 6, 'N')
    # 耳朵
    rect(g, 28, 56, 6, 5, 'R')
    px(g, 29, 55, 'R'); px(g, 33, 55, 'R')
    rect(g, 29, 57, 3, 3, 'r')
    # 獠牙（两根，向上弯，明显）
    for tx, ty in [(8, 89), (7, 88), (6, 86), (5, 84), (4, 82), (3, 80)]:
        rect(g, tx, ty, 2, 2, 'W')
    px(g, 3, 79, 'W')
    for tx, ty in [(12, 90), (11, 89)]:
        rect(g, tx, ty, 2, 2, 'w')
    # 鬃毛：贴背线的深色脊带与尖刺
    for x in range(36, 85):
        ytop = None
        for y in range(0, 128):
            if g[y][x] != '.':
                ytop = y
                break
        if ytop is None:
            continue
        px(g, x, ytop, 'M')
        if x % 4 < 2:
            px(g, x, ytop + 1, 'M')
        if x % 6 == 0:
            px(g, x, ytop - 1, 'M')
            px(g, x, ytop - 2, 'M')
    # 四条短腿
    rect(g, 32, 100, 8, 23, 'R')
    rect(g, 44, 102, 8, 21, 'r')
    rect(g, 64, 102, 8, 21, 'R')
    rect(g, 76, 100, 8, 23, 'r')
    # 蹄
    rect(g, 32, 120, 8, 3, 'M')
    rect(g, 44, 120, 8, 3, 'M')
    rect(g, 64, 120, 8, 3, 'M')
    rect(g, 76, 120, 8, 3, 'M')
    # 尾巴
    px(g, 86, 76, 'R'); px(g, 87, 75, 'R'); px(g, 88, 76, 'M')
    outline(g)
    # 眼睛与怒眉
    px(g, 20, 72, 'K')
    px(g, 21, 72, 'K')
    rect(g, 18, 69, 6, 2, 'M')
    # 鼻孔
    px(g, 5, 81, 'K')
    px(g, 5, 84, 'K')
    # 腹部阴影
    shade_bottom(g, {'R': 'r', 'N': 'r'})
    return g


def build_club():
    g = make_canvas(16, 32)
    # 棒头（上宽）
    rect(g, 3, 3, 10, 4, 'B')
    rect(g, 4, 2, 8, 6, 'B')
    # 棒身
    rect(g, 6, 8, 4, 16, 'B')
    # 尾端
    rect(g, 5, 24, 6, 3, 'B')
    outline(g)
    # 木头高光
    rect(g, 5, 3, 3, 3, 'L')
    rect(g, 7, 8, 1, 15, 'L')
    # 握把缠布
    rect(g, 6, 20, 4, 1, 'W')
    rect(g, 6, 22, 4, 1, 'W')
    # 木节
    px(g, 10, 10, 'b')
    px(g, 6, 15, 'b')
    return g


def build_sling():
    g = make_canvas(24, 24)
    # 手柄
    rect(g, 10, 13, 4, 8, 'B')
    # Y 形叉
    line(g, 11, 13, 7, 5, 'B', 2)
    line(g, 12, 13, 16, 5, 'B', 2)
    # 皮兜
    rect(g, 9, 7, 6, 4, 'b')
    # 皮绳
    line(g, 7, 5, 9, 8, 'b', 1)
    line(g, 16, 5, 14, 8, 'b', 1)
    outline(g)
    # 手柄缠布
    rect(g, 10, 17, 4, 1, 'W')
    # 兜中石子
    px(g, 11, 8, 'U')
    px(g, 12, 8, 'U')
    return g


def build_stone():
    g = make_canvas(12, 12)
    ellipse(g, 6, 6, 4, 4, 'U')
    outline(g)
    px(g, 4, 4, 'V')
    px(g, 5, 3, 'V')
    shade_bottom(g, {'U': 'u'})
    return g


def build_tiger():
    g = make_canvas(48, 36)
    # 身体
    rect(g, 10, 14, 26, 9, 'O')
    # 胸肩
    rect(g, 6, 12, 8, 10, 'O')
    # 头
    rect(g, 2, 8, 9, 8, 'O')
    # 米白吻部（前伸）
    rect(g, 1, 11, 4, 4, 'W')
    # 耳朵
    px(g, 4, 6, 'O'); px(g, 5, 7, 'O'); px(g, 4, 7, 'O')
    px(g, 8, 6, 'O'); px(g, 9, 7, 'O'); px(g, 8, 7, 'O')
    # 四条腿
    rect(g, 9, 22, 3, 8, 'O')
    rect(g, 14, 22, 3, 8, 'O')
    rect(g, 26, 22, 3, 8, 'O')
    rect(g, 31, 22, 3, 8, 'O')
    # 尾巴（上卷）
    rect(g, 35, 10, 3, 3, 'O')
    rect(g, 37, 8, 3, 3, 'O')
    px(g, 40, 7, 'O')
    outline(g)
    # 黑条纹
    for sx in (14, 19, 24, 29, 33):
        rect(g, sx, 14, 2, 4, 'T')
    rect(g, 12, 12, 2, 3, 'T')
    px(g, 4, 9, 'T'); px(g, 6, 8, 'T'); px(g, 8, 9, 'T')
    # 眼睛、鼻子
    px(g, 4, 10, 'K')
    px(g, 1, 11, 'K')
    # 腹部米白
    rect(g, 11, 21, 24, 1, 'W')
    # 腿爪阴影
    rect(g, 9, 28, 3, 1, 'o')
    rect(g, 14, 28, 3, 1, 'o')
    rect(g, 26, 28, 3, 1, 'o')
    rect(g, 31, 28, 3, 1, 'o')
    # 尾尖
    px(g, 40, 7, 'T')
    px(g, 39, 8, 'T')
    return g


def build_wolf_king():
    g = make_canvas(40, 32)
    # 鬃毛（颈肩，先画）
    rect(g, 7, 9, 9, 10, 'Q')
    px(g, 7, 8, 'Q'); px(g, 10, 8, 'Q'); px(g, 13, 8, 'Q')
    px(g, 6, 12, 'Q'); px(g, 6, 15, 'Q'); px(g, 6, 18, 'Q')
    # 身体
    rect(g, 11, 12, 20, 8, 'Z')
    # 头
    rect(g, 3, 8, 7, 7, 'Z')
    # 吻部
    rect(g, 1, 11, 3, 3, 'Z')
    # 耳朵
    px(g, 4, 6, 'Z'); px(g, 5, 7, 'Z')
    px(g, 7, 6, 'Z'); px(g, 8, 7, 'Z')
    # 四条腿
    rect(g, 11, 19, 3, 8, 'Z')
    rect(g, 15, 19, 3, 8, 'Z')
    rect(g, 23, 19, 3, 8, 'Z')
    rect(g, 27, 19, 3, 8, 'Z')
    # 尾巴（蓬松）
    rect(g, 30, 10, 4, 4, 'Z')
    rect(g, 32, 8, 4, 4, 'Z')
    px(g, 36, 9, 'Z')
    outline(g)
    # 琥珀眼、伤疤
    px(g, 4, 10, 'Y')
    px(g, 6, 12, 'w')
    # 腹部阴影
    rect(g, 12, 18, 18, 1, 'z')
    # 鬃毛下部阴影
    rect(g, 8, 17, 7, 1, 'z')
    # 腿下部阴影
    rect(g, 11, 25, 3, 1, 'z')
    rect(g, 15, 25, 3, 1, 'z')
    rect(g, 23, 25, 3, 1, 'z')
    rect(g, 27, 25, 3, 1, 'z')
    # 尾尖浅灰
    px(g, 36, 9, 'Q')
    px(g, 35, 8, 'Q')
    return g


def build_sheet(images):
    scale_map = {
        'player': 5, 'wolf': 5, 'wolf_king': 4, 'tiger': 4,
        'boar_king': 2, 'club': 5, 'sling': 5, 'stone': 8,
    }
    pad = 28
    label_h = 18
    items = []
    for name, img in images:
        s = scale_map.get(name, 4)
        big = img.resize((img.width * s, img.height * s), Image.Resampling.NEAREST)
        items.append((name, big))
    total_w = sum(i.width for _, i in items) + pad * (len(items) + 1)
    max_h = max(i.height for _, i in items) + label_h + pad * 2
    sheet = Image.new('RGBA', (total_w, max_h), (0x31, 0x95, 0x6A, 255))
    x = pad
    from PIL import ImageDraw
    draw = ImageDraw.Draw(sheet)
    for name, big in items:
        y = pad + (max_h - pad * 2 - label_h - big.height) // 2
        sheet.paste(big, (x, y), big)
        draw.text((x, y + big.height + 4), name, fill=(0xF2, 0xEA, 0xD8, 255))
        x += big.width + pad
    sheet.save(os.path.join(OUT_DIR, 'preview_sheet.png'))


def main():
    builders = [
        ('player', build_player),
        ('wolf', build_wolf),
        ('boar_king', build_boar_king),
        ('tiger', build_tiger),
        ('wolf_king', build_wolf_king),
        ('club', build_club),
        ('sling', build_sling),
        ('stone', build_stone),
    ]
    images = []
    for name, fn in builders:
        grid = fn()
        img = save(grid, name)
        images.append((name, img))
        print(name, img.size)
    build_sheet(images)
    print('preview_sheet saved')


if __name__ == '__main__':
    main()
