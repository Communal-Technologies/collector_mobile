"""The collector's launcher icons, derived from the member app's mark.

The two apps sit next to each other in the drawer and the tint is how you tell
them apart: the member's mark is purple, the collector's is black on the same
white ground. So this takes the member app's own PNGs — whose alpha channel *is*
the mark, at the fleet's geometry — and repaints them, rather than keeping a
second hand-cut copy that drifts. The white mark is the one Android 12+ centres
on the launch window, cropped to the ink because that drawable carries its own
padding (res/drawable/splash_mark.xml).

Run this after tool/refit_launcher_mark.py in the member app, then
`dart run flutter_launcher_icons`.

    python3 tool/make_icons.py
"""

from PIL import Image

SRC_FULL = "../mobile/assets/images/launcher_icon.png"
SRC_ADAPTIVE = "../mobile/assets/images/launcher_icon_foreground.png"
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)


def coverage(path):
    return Image.open(path).convert("RGBA").split()[3]


def paint(mask, colour):
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", mask.size, colour + (255,)), (0, 0), mask)
    return out


full = coverage(SRC_FULL)
adaptive = coverage(SRC_ADAPTIVE)

paint(full, BLACK).save("assets/images/launcher_icon_black.png")
paint(adaptive, BLACK).save("assets/images/launcher_icon_foreground_black.png")

white = paint(adaptive, WHITE)
art = white.crop(white.getbbox())
side = max(art.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
square.resize((1024, 1024), Image.LANCZOS).save(
    "android/app/src/main/res/drawable-nodpi/brand_mark_white.png"
)
