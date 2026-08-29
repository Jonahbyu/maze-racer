"""Generate the Maze Racer icon.

Draws a small maze in the game's neon palette with a bright racer trail cutting
through it, then writes a multi-resolution .ico for the desktop shortcut and a
.svg-free PNG for the Godot window icon.

Run:  python tools/make_icon.py
"""

from PIL import Image, ImageDraw
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Match the in-game palette (MazeMesh.gd).
BG = (8, 12, 22, 255)
WALL = (31, 217, 255, 255)
WALL_DIM = (14, 46, 68, 255)
TRAIL = (90, 255, 140, 255)

# A hand-laid 8x8 maze. 1 = wall, 0 = corridor.
GRID = [
    [1, 1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 1, 0, 0, 1],
    [1, 0, 1, 0, 1, 0, 1, 1],
    [1, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 1, 1, 0, 1],
    [1, 0, 0, 0, 0, 1, 0, 1],
    [1, 1, 1, 1, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 1],
]

# The racer's route through it, as (col, row) cells.
TRAIL_CELLS = [
    (1, 1), (1, 2), (1, 3), (1, 4), (1, 5),
    (2, 5), (3, 5), (4, 5), (4, 6), (5, 6), (6, 6),
]


def render(size):
    # Supersample, then downscale -- gives clean edges without any AA work.
    scale = 8
    s = size * scale
    img = Image.new("RGBA", (s, s), BG)
    draw = ImageDraw.Draw(img)

    cells = len(GRID)
    cell = s / cells

    # Walls, dim bodies first.
    for row in range(cells):
        for col in range(cells):
            if GRID[row][col]:
                x0, y0 = col * cell, row * cell
                draw.rectangle([x0, y0, x0 + cell, y0 + cell], fill=WALL_DIM)

    # Then a bright edge ONLY where a wall borders a corridor. Lighting every
    # wall's top edge instead turns the solid blocks into horizontal stripes,
    # because interior walls stack against each other.
    edge = max(1, int(cell * 0.20))
    for row in range(cells):
        for col in range(cells):
            if not GRID[row][col]:
                continue
            x0, y0 = col * cell, row * cell
            x1, y1 = x0 + cell, y0 + cell

            def open_at(r, c):
                return 0 <= r < cells and 0 <= c < cells and not GRID[r][c]

            if open_at(row - 1, col):
                draw.rectangle([x0, y0, x1, y0 + edge], fill=WALL)
            if open_at(row + 1, col):
                draw.rectangle([x0, y1 - edge, x1, y1], fill=WALL)
            if open_at(row, col - 1):
                draw.rectangle([x0, y0, x0 + edge, y1], fill=WALL)
            if open_at(row, col + 1):
                draw.rectangle([x1 - edge, y0, x1, y1], fill=WALL)

    # The trail, drawn as a thick line through the corridor centres.
    points = [((c + 0.5) * cell, (r + 0.5) * cell) for c, r in TRAIL_CELLS]
    draw.line(points, fill=TRAIL, width=int(cell * 0.34), joint="curve")

    # A brighter head on the leading end.
    hx, hy = points[-1]
    r = cell * 0.30
    draw.ellipse([hx - r, hy - r, hx + r, hy + r], fill=(180, 255, 200, 255))

    return img.resize((size, size), Image.LANCZOS)


def main():
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = [render(n) for n in sizes]

    ico_path = os.path.join(HERE, "MazeRacer.ico")
    images[-1].save(ico_path, format="ICO",
                    sizes=[(n, n) for n in sizes])
    print("wrote", ico_path)

    png_path = os.path.join(ROOT, "icon.png")
    render(256).save(png_path)
    print("wrote", png_path)


if __name__ == "__main__":
    main()
