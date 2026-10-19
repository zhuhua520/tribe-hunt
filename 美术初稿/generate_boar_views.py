# 野猪三视图生成器：按用户提供的野猪照片像素化，棕黑配色
# 用法：python generate_boar_views.py
# 产物：boar_side.png / boar_front.png / boar_back.png / boar_three_views.png
import math
import os
from PIL import Image, ImageDraw

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

PALETTE = {
    'K': (0x14, 0x0D, 0x08, 255),  # 描边（近黑棕）
    'R': (0x3A, 0x2A, 0x1C, 255),  # 身体主色（深棕）
    'r': (0x28, 0x1C, 0x10, 255),  # 身体阴影
    'M': (0x5A, 0x41, 0x30, 255),  # 肩颈鬃带（中棕）
    'N': (0x4A, 0x36, 0x26, 255),  # 鼻吻
    'n': (0x63, 0x50, 0x4A, 255),  # 鼻盘
    'c': (0x4E, 0x3E, 0x38, 255),  # 鼻盘暗
    'H': (0x17, 0x10, 0x0A, 255),  # 蹄
    'E': (0x0D, 0x09, 0x06, 255),  # 眼
    'W': (0xE8, 0xDC, 0xC8, 255),  # 獠牙
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


def top_of(grid, x):
    for y in range(len(grid)):
        if grid[y][x] != '.':
            return y
    return None


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


def build_side():
    g = make_canvas(64, 44)
    # 身体与肩峰
    ellipse(g, 36, 25, 22, 13, 'R')
    ellipse(g, 23, 17, 12, 9, 'R')
    # 头
    ellipse(g, 15, 23, 9, 8, 'R')
    # 鼻吻与鼻盘
    ellipse(g, 8, 28, 5, 4, 'N')
    ellipse(g, 4, 29, 2, 3, 'n')
    # 耳朵（尖，略后抿）
    rect(g, 18, 13, 4, 3, 'R')
    px(g, 19, 12, 'R'); px(g, 20, 12, 'R')
    rect(g, 19, 14, 2, 2, 'r')
    # 鬃带：肩背浅色带与尖刺
    for x in range(12, 36):
        ytop = top_of(g, x)
        if ytop is None:
            continue
        px(g, x, ytop, 'M')
        if x % 4 < 2:
            px(g, x, ytop + 1, 'M')
        if x % 5 == 2:
            px(g, x, ytop - 1, 'M')
    # 肩部鬣毛碎点
    for fx, fy in [(16, 12), (20, 15), (24, 11), (28, 14), (14, 16), (26, 17)]:
        px(g, fx, fy, 'M')
    # 四条腿（近深远浅）
    rect(g, 16, 33, 4, 9, 'R')
    rect(g, 22, 34, 4, 8, 'r')
    rect(g, 45, 33, 4, 9, 'R')
    rect(g, 51, 34, 4, 8, 'r')
    # 蹄
    rect(g, 16, 40, 4, 2, 'H')
    rect(g, 22, 40, 4, 2, 'H')
    rect(g, 45, 40, 4, 2, 'H')
    rect(g, 51, 40, 4, 2, 'H')
    # 尾巴
    px(g, 58, 22, 'R'); px(g, 59, 23, 'r'); px(g, 60, 24, 'r'); px(g, 60, 25, 'M')
    # 小獠牙
    px(g, 6, 32, 'W')
    outline(g)
    # 眼睛与眼周浅斑
    px(g, 14, 21, 'E')
    px(g, 13, 19, 'M'); px(g, 14, 19, 'M')
    # 鼻孔
    px(g, 3, 28, 'K'); px(g, 3, 30, 'K')
    shade_bottom(g, {'R': 'r', 'N': 'r', 'n': 'c'})
    return g


def build_front():
    g = make_canvas(40, 44)
    # 身体（在后）
    ellipse(g, 20, 28, 14, 10, 'R')
    # 头（在前，占主视觉）
    ellipse(g, 20, 21, 11, 10, 'R')
    # 耳朵（对称，尖部外撇）
    rect(g, 11, 12, 4, 3, 'R'); px(g, 10, 11, 'R'); px(g, 11, 11, 'R'); px(g, 10, 10, 'R')
    rect(g, 25, 12, 4, 3, 'R'); px(g, 28, 11, 'R'); px(g, 29, 11, 'R'); px(g, 29, 10, 'R')
    rect(g, 12, 13, 2, 2, 'r')
    rect(g, 26, 13, 2, 2, 'r')
    # 耳间鬃带
    rect(g, 14, 11, 12, 2, 'M')
    px(g, 17, 10, 'M'); px(g, 21, 10, 'M')
    # 肩部鬃带（头的两侧露出）
    rect(g, 7, 19, 3, 3, 'M')
    rect(g, 30, 19, 3, 3, 'M')
    # 鼻梁与鼻盘
    rect(g, 19, 22, 2, 4, 'N')
    ellipse(g, 20, 28, 5, 4, 'n')
    # 小獠牙
    px(g, 14, 31, 'W')
    px(g, 25, 31, 'W')
    # 前腿与后腿露边
    rect(g, 15, 34, 4, 8, 'R')
    rect(g, 21, 34, 4, 8, 'R')
    rect(g, 7, 35, 3, 6, 'r')
    rect(g, 30, 35, 3, 6, 'r')
    # 蹄
    rect(g, 15, 40, 4, 2, 'H')
    rect(g, 21, 40, 4, 2, 'H')
    rect(g, 7, 39, 3, 2, 'H')
    rect(g, 30, 39, 3, 2, 'H')
    outline(g)
    # 眼睛与眼周浅斑
    px(g, 13, 19, 'E')
    px(g, 26, 19, 'E')
    px(g, 13, 18, 'M')
    px(g, 26, 18, 'M')
    # 鼻孔
    px(g, 18, 28, 'K')
    px(g, 22, 28, 'K')
    # 胸口阴影
    rect(g, 18, 32, 4, 2, 'r')
    shade_bottom(g, {'R': 'r', 'N': 'r', 'n': 'c'})
    return g


def build_back():
    g = make_canvas(40, 44)
    # 臀部主体
    ellipse(g, 20, 25, 15, 13, 'R')
    # 耳朵（从背后露出）
    rect(g, 8, 11, 4, 4, 'R'); px(g, 9, 10, 'R'); px(g, 10, 10, 'R')
    rect(g, 28, 11, 4, 4, 'R'); px(g, 29, 10, 'R'); px(g, 30, 10, 'R')
    rect(g, 9, 12, 2, 2, 'r')
    rect(g, 29, 12, 2, 2, 'r')
    # 背脊鬃带（沿顶线，带尖刺）
    for x in range(10, 31):
        ytop = top_of(g, x)
        if ytop is None:
            continue
        px(g, x, ytop, 'M')
        if x % 4 < 2:
            px(g, x, ytop + 1, 'M')
        if x % 5 == 0:
            px(g, x, ytop - 1, 'M')
    # 尾巴（自臀顶垂下，末端毛簇）
    rect(g, 19, 12, 2, 8, 'r')
    rect(g, 18, 19, 4, 3, 'M')
    # 后腿
    rect(g, 13, 33, 5, 8, 'R')
    rect(g, 22, 33, 5, 8, 'R')
    # 蹄
    rect(g, 13, 40, 5, 2, 'H')
    rect(g, 22, 40, 5, 2, 'H')
    outline(g)
    shade_bottom(g, {'R': 'r'})
    return g


def build_sheet(images):
    pad = 28
    label_h = 18
    scale = 5
    items = []
    for name, img in images:
        big = img.resize((img.width * scale, img.height * scale), Image.Resampling.NEAREST)
        items.append((name, big))
    total_w = sum(i.width for _, i in items) + pad * (len(items) + 1)
    max_h = max(i.height for _, i in items) + label_h + pad * 2
    sheet = Image.new('RGBA', (total_w, max_h), (0xC9, 0xBF, 0xA8, 255))
    draw = ImageDraw.Draw(sheet)
    x = pad
    for name, big in items:
        y = pad + (max_h - pad * 2 - label_h - big.height) // 2
        sheet.paste(big, (x, y), big)
        draw.text((x, y + big.height + 4), name, fill=(0x2E, 0x1B, 0x12, 255))
        x += big.width + pad
    sheet.save(os.path.join(OUT_DIR, 'boar_three_views.png'))


def main():
    builders = [
        ('boar_side', build_side),
        ('boar_front', build_front),
        ('boar_back', build_back),
    ]
    images = []
    for name, fn in builders:
        grid = fn()
        img = save(grid, name)
        images.append((name, img))
        print(name, img.size)
    build_sheet(images)
    print('boar_three_views saved')


if __name__ == '__main__':
    main()
