#!/usr/bin/env python3
"""Generates the ThrowLab logo: a minimalist rounded Erlenmeyer flask pierced
by a javelin, light-blue line art on white. Outputs the launcher icon, the
adaptive-icon foreground, and a transparent logo for in-app use."""
import math
from PIL import Image, ImageDraw

S = 2  # supersample factor; drawn at 2048, downscaled to 1024
W = 1024 * S
BLUE = (79, 195, 247, 255)   # light blue 300
LIGHT = (179, 229, 252, 255)  # light blue 100

WALL_W = 28
# Javelin: tail lower-left, tip upper-right, piercing the flask body.
TAIL = (150, 790)
TIP = (880, 235)
# Silhouette of a real javelin: a needle that is widest just behind the head
# and tapers over the whole back half to a hairline tail, with the wrapped
# cord grip bulging slightly at the balance point.
WMAX = 9.5          # half-width of the widest section of the shaft
SHOULDER = 0.55     # where the taper from the tail reaches full width
GRIP = (0.655, 0.745)  # cord binding, just ahead of where the shaft exits
HEAD = 0.855        # where the metal head joins the shaft
CORD = 3.0          # extra half-width contributed by the wrapped cord


def pt(p):
    return (p[0] * S, p[1] * S)


def stroke(draw, points, width, fill):
    points = [pt(p) for p in points]
    draw.line(points, fill=fill, width=width * S, joint="curve")
    r = width * S / 2
    for p in (points[0], points[-1]):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def qbez(p0, p1, p2, n=24):
    """Quadratic bezier sampled as a polyline."""
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / n for i in range(n + 1))]


def flask_wall(side):
    """Smooth wall path: neck, rounded shoulder, cone, rounded base corner.
    side = -1 for left, +1 for right (mirrored around x=480)."""
    def m(x):
        return 480 + side * (x - 480)

    neck_x, shoulder_y = m(436), 380
    cone_top = (436, 380)
    cone_bot = (300, 810)
    ux = (cone_bot[0] - cone_top[0]) / 451.0
    uy = (cone_bot[1] - cone_top[1]) / 451.0
    shoulder_end = (m(436 + 70 * ux), 380 + 70 * uy)
    corner_start = (m(300 - 55 * ux), 810 - 55 * uy)

    path = [(neck_x, 172), (neck_x, 330)]
    path += qbez((neck_x, 330), (neck_x, 398), shoulder_end)
    path.append(corner_start)
    path += qbez(corner_start, (m(300), 810), (m(352), 810))
    return path


LEFT_WALL = flask_wall(-1)
RIGHT_WALL = flask_wall(1)
BASE = [(352, 810), (608, 810)]
LIP = [(410, 172), (550, 172)]


def along_javelin(t):
    return (TAIL[0] + (TIP[0] - TAIL[0]) * t, TAIL[1] + (TIP[1] - TAIL[1]) * t)


def axis():
    """Unit vector along the javelin and its perpendicular."""
    ux, uy = TIP[0] - TAIL[0], TIP[1] - TAIL[1]
    length = math.hypot(ux, uy)
    ux, uy = ux / length, uy / length
    return (ux, uy), (-uy, ux)


def half_width(t):
    """Half-width of the javelin at fraction t along its axis (0 = tail,
    1 = point): a long slow taper up from the tail, a constant widest
    section, the cord grip bulge, then the metal head drawn to a point."""
    if t >= HEAD:
        w = WMAX * (1 - (t - HEAD) / (1 - HEAD)) ** 0.85
    elif t >= SHOULDER:
        w = WMAX
    else:
        w = WMAX * (t / SHOULDER) ** 1.15
    if GRIP[0] <= t <= GRIP[1]:
        # Rounded shoulders so the binding reads as a wrap, not a box.
        w += CORD * min(1.0, min(t - GRIP[0], GRIP[1] - t) / 0.02)
    return w


def javelin_outline(n=400):
    """Closed silhouette: one side of the profile, then the other back."""
    (ux, uy), (px, py) = axis()
    side_a, side_b = [], []
    for i in range(n + 1):
        t = i / n
        cx, cy = along_javelin(t)
        w = half_width(t)
        side_a.append((cx + px * w, cy + py * w))
        side_b.append((cx - px * w, cy - py * w))
    return side_a + side_b[::-1]


def render(background):
    img = Image.new("RGBA", (W, W), background)
    draw = ImageDraw.Draw(img)

    # Javelin first, so the flask walls can pass "in front" of it.
    _, (px, py) = axis()
    draw.polygon([pt(p) for p in javelin_outline()], fill=BLUE)
    # Binding lines across the cord grip.
    for t in (0.675, 0.700, 0.725):
        cx, cy = along_javelin(t)
        w = half_width(t) - 1
        stroke(draw, [(cx + px * w, cy + py * w),
                      (cx - px * w, cy - py * w)], 5, LIGHT)

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
    stroke(draw, [(369, 680), (591, 680)], 20, LIGHT)
    for (cx, cy, r) in ((455, 585, 16), (515, 540, 10)):
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
