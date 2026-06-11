#!/usr/bin/env python3
"""Generates the ThrowLab logo: a minimalist Erlenmeyer flask pierced by a
javelin, light-blue line art on white. Outputs the launcher icon, the
adaptive-icon foreground, and a transparent logo for in-app use."""
import math
from PIL import Image, ImageDraw

S = 2  # supersample factor; drawn at 2048, downscaled to 1024
W = 1024 * S
BLUE = (79, 195, 247, 255)   # light blue 300
LIGHT = (179, 229, 252, 255)  # light blue 100

# Flask geometry (1024 space): neck, shoulder, conical body, base.
LEFT_WALL = [(436, 170), (436, 380), (300, 810)]
RIGHT_WALL = [(524, 170), (524, 380), (660, 810)]
BASE = [(300, 810), (660, 810)]
LIP = [(412, 170), (548, 170)]
WALL_W = 30
# Javelin: tail lower-left, tip upper-right, piercing the flask body.
TAIL = (150, 790)
TIP = (880, 235)
SHAFT_W = 22


def pt(p):
    return (p[0] * S, p[1] * S)


def stroke(draw, points, width, fill):
    points = [pt(p) for p in points]
    draw.line(points, fill=fill, width=width * S, joint="curve")
    r = width * S / 2
    for p in (points[0], points[-1]):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def along_javelin(t):
    return (TAIL[0] + (TIP[0] - TAIL[0]) * t, TAIL[1] + (TIP[1] - TAIL[1]) * t)


def render(background):
    img = Image.new("RGBA", (W, W), background)
    draw = ImageDraw.Draw(img)

    # Javelin first, so the flask walls can pass "in front" of it.
    ux, uy = TIP[0] - TAIL[0], TIP[1] - TAIL[1]
    length = math.hypot(ux, uy)
    ux, uy = ux / length, uy / length
    shaft_end = (TIP[0] - 70 * ux, TIP[1] - 70 * uy)
    stroke(draw, [TAIL, shaft_end], SHAFT_W, BLUE)
    # Spear tip: slim filled triangle continuing the shaft.
    px, py = -uy, ux  # perpendicular
    half = 26
    draw.polygon(
        [pt(TIP),
         pt((shaft_end[0] + px * half, shaft_end[1] + py * half)),
         pt((shaft_end[0] - px * half, shaft_end[1] - py * half))],
        fill=BLUE)
    # Cord grip: two short ticks across the shaft, below the flask.
    for t in (0.08, 0.14):
        cx, cy = along_javelin(t)
        tick = 30
        stroke(draw, [(cx + px * tick, cy + py * tick),
                      (cx - px * tick, cy - py * tick)], 12, BLUE)

    # Erase a halo along the flask walls so the shaft reads as piercing
    # through the glass rather than lying on top of it.
    halo = Image.new("L", (W, W), 0)
    halo_draw = ImageDraw.Draw(halo)
    for path in (LEFT_WALL, RIGHT_WALL):
        halo_draw.line([pt(p) for p in path], fill=255, width=64 * S,
                       joint="curve")
    img.paste(background, mask=halo)
    draw = ImageDraw.Draw(img)

    # Flask outline.
    for path in (LEFT_WALL, RIGHT_WALL, BASE, LIP):
        stroke(draw, path, WALL_W, BLUE)
    # Liquid line + bubbles in a lighter shade.
    stroke(draw, [(366, 680), (594, 680)], 20, LIGHT)
    for (cx, cy, r) in ((470, 590, 16), (525, 525, 10)):
        bb = [pt((cx - r, cy - r)), pt((cx + r, cy + r))]
        draw.ellipse([*bb[0], *bb[1]], outline=LIGHT, width=12 * S)

    return img.resize((1024, 1024), Image.LANCZOS)


icon = render((255, 255, 255, 255))
icon.save("assets/icon/icon.png")

logo = render((0, 0, 0, 0))
logo.save("assets/icon/logo.png")

# Adaptive foreground: drawing scaled into the ~66% safe zone.
fg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
small = logo.resize((624, 624), Image.LANCZOS)
fg.paste(small, (200, 200), small)
fg.save("assets/icon/icon_foreground.png")
print("icons written")
