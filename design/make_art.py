"""
KeyPort artwork builder.

Renders the CurseForge asset set into design/ :

    keyport-icon-400.png          CurseForge project avatar (400x400)
    keyport-icon-64.png           small-size legibility check
    keyport-banner.png            header art for the description
    keyport-gallery-command.png   "one command, everyone gets it" explainer
    keyport-gallery-codes.png     the /kp list chat output
    keyport-popup.png             the popup alone, transparent background

Body images are capped at BODY_W (840px) because CurseForge's description
column clips anything wider; the uncut renders go to full-size/ for the
gallery lightbox.

The popup geometry below is copied from KeyPort.lua so the mockup cannot drift
from the addon: change one, change the other.

Note on PIL: ImageDraw *replaces* pixels, alpha included, so every translucent
fill and every drop shadow goes onto its own layer and is alpha_composited --
drawing them straight onto the canvas punches holes through it.

    python design/make_art.py
"""

import os
from PIL import Image, ImageDraw, ImageEnhance, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "raw")
OUT = ROOT
FULL = os.path.join(ROOT, "full-size")

# CurseForge's description column clips anything wider than ~850px, so every
# body image ships at this width. The uncut renders go to full-size/ for the
# gallery lightbox, where the extra resolution is worth having.
BODY_W = 840


def save_pair(canvas, name):
    """Write the full-size render and the description-width copy."""
    os.makedirs(FULL, exist_ok=True)
    canvas.convert("RGB").save(os.path.join(FULL, name))
    if canvas.width > BODY_W:
        height = round(canvas.height * BODY_W / canvas.width)
        canvas = canvas.resize((BODY_W, height), Image.LANCZOS)
    canvas.convert("RGB").save(os.path.join(OUT, name))
    return canvas

# --- layout constants, mirroring KeyPort.lua -------------------------------
PANEL_W, HEADER_H, EDGE = 220, 26, 10
NAME_Y, NAME_H = HEADER_H + 8, 24
BUTTON_Y, BUTTON_H, ICON_SZ = NAME_Y + NAME_H, 54, 38
FOOTER_Y, FOOTER_H = BUTTON_Y + BUTTON_H + 7, 14
PANEL_H = FOOTER_Y + FOOTER_H + 9

# --- picker geometry, mirroring KeyPort.lua --------------------------------
LIST_W, ROW_H, MAX_ROWS = 320, 26, 5
AVATAR_SZ, DUNGEON_SZ = 20, 18
LIST_PAD, TAB_H, COLHDR_H = 8, 22, 14
NAME_W, SCORE_W = 64, 36
ROW_FONT = 10

# --- palette ---------------------------------------------------------------
ACCENT = (89, 199, 255)
GOLD = (255, 209, 0)
ABOVE = (64, 224, 112)
GREY = (150, 150, 150)
INK = (8, 9, 12)

# --- fonts -----------------------------------------------------------------
# Friz Quadrata (WoW's default UI face) is not distributable; Georgia Bold is
# the closest stand-in on a stock Windows box. Cinzel carries the wordmark.
UI_FONT = "C:/Windows/Fonts/georgiab.ttf"
UI_FONT_REG = "C:/Windows/Fonts/georgia.ttf"
DISPLAY_FONT = ("D:/Games/Blizzard/World of Warcraft/_retail_/Interface/AddOns/"
                "EllesmereUI/media/fonts/Cinzel Decorative.ttf")
BODY_FONT = "C:/Windows/Fonts/segoeui.ttf"
BODY_FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"
MONO_FONT = "C:/Windows/Fonts/consola.ttf"
MONO_FONT_BOLD = "C:/Windows/Fonts/consolab.ttf"

_MEASURE = ImageDraw.Draw(Image.new("RGBA", (1, 1)))


def font(path, size):
    return ImageFont.truetype(path, size)


def width_of(string, fnt):
    return _MEASURE.textlength(string, font=fnt)


# --- compositing helpers ---------------------------------------------------
def fill(img, box, colour):
    """Alpha-composite a solid rectangle (unlike ImageDraw, which overwrites)."""
    x0, y0, x1, y1 = (round(v) for v in box)
    if x1 <= x0 or y1 <= y0:
        return
    img.alpha_composite(Image.new("RGBA", (x1 - x0, y1 - y0), colour), (x0, y0))


def frame(img, box, colour, width=1):
    x0, y0, x1, y1 = (round(v) for v in box)
    fill(img, (x0, y0, x1, y0 + width), colour)
    fill(img, (x0, y1 - width, x1, y1), colour)
    fill(img, (x0, y0, x0 + width, y1), colour)
    fill(img, (x1 - width, y0, x1, y1), colour)


def text(img, xy, string, fnt, colour, anchor="la", shadow=(0, 0, 0, 200), offset=1):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if shadow:
        d.text((xy[0] + offset, xy[1] + offset), string, font=fnt, fill=shadow, anchor=anchor)
    d.text(xy, string, font=fnt, fill=colour, anchor=anchor)
    img.alpha_composite(layer)


def vgradient(size, top, bottom):
    """Vertical gradient as RGBA (top colour at y=0)."""
    w, h = size
    strip = Image.new("RGBA", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return strip.resize(size, Image.BILINEAR)


def glow(size, colour, radius):
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        (w * 0.5 - radius, h * 0.5 - radius, w * 0.5 + radius, h * 0.5 + radius), fill=colour)
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def shadowed(img, blur=18, alpha=170, spread=8):
    pad = blur * 3
    canvas = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    shade = Image.new("RGBA", (img.width + spread * 2, img.height + spread * 2), (0, 0, 0, alpha))
    canvas.alpha_composite(shade, (pad - spread, pad - spread + spread))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(img, (pad, pad))
    return canvas


# ---------------------------------------------------------------------------
#  Spell icon: a stand-in portal glyph, not Blizzard art.
# ---------------------------------------------------------------------------
def portal_icon(size):
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=s * 0.08, fill=(9, 15, 28, 255))
    img.alpha_composite(glow((s, s), (55, 150, 235, 200), s * 0.30))

    cx = cy = s / 2
    d = ImageDraw.Draw(img)
    for i, (r, w, a) in enumerate([(s * 0.34, s * 0.055, 240),
                                   (s * 0.25, s * 0.045, 210),
                                   (s * 0.16, s * 0.035, 180)]):
        start = 25 + i * 95
        d.arc((cx - r, cy - r, cx + r, cy + r), start, start + 280,
              fill=(165, 230, 255, a), width=round(w))
    d.ellipse((cx - s * 0.08, cy - s * 0.08, cx + s * 0.08, cy + s * 0.08),
              fill=(232, 248, 255, 255))

    img = img.filter(ImageFilter.GaussianBlur(s * 0.004))
    img = img.resize((size, size), Image.LANCZOS)
    frame(img, (0, 0, size, size), (0, 0, 0, 200), max(1, size // 24))
    return img


# ---------------------------------------------------------------------------
#  The popup, at an integer magnification of the real frame.
# ---------------------------------------------------------------------------
def popup(scale=4, dungeon="Kings' Rest", level=10, footer="Sent to your party",
          caption="Teleport", above=False):
    S = scale
    W, H = PANEL_W * S, PANEL_H * S
    img = Image.new("RGBA", (W, H), (13, 13, 15, 255))

    # sheen: KeyPort.lua sets a VERTICAL gradient, strongest at the top edge
    sheen_h = round(PANEL_H * 0.6) * S
    img.alpha_composite(vgradient((W - 2 * S, sheen_h), (41, 61, 82, 140), (26, 36, 46, 0)), (S, S))

    frame(img, (0, 0, W, H), (0, 0, 0, 255), S)

    header_bottom = S + HEADER_H * S
    fill(img, (S, S, W - S, header_bottom), (0, 0, 0, 115))
    fill(img, (S, header_bottom, W - S, header_bottom + S), ACCENT + (140,))

    f_title = font(UI_FONT, 11 * S)
    f_name = font(UI_FONT, 13 * S)
    f_caption = font(UI_FONT, 12 * S)
    f_footer = font(UI_FONT_REG, 10 * S)

    header_mid = S + HEADER_H * S / 2
    text(img, (EDGE * S, header_mid), "KeyPort", f_title, ACCENT, anchor="lm", offset=S / 4)

    # close glyph, drawn rather than typeset so it stays symmetrical
    cx, cy, arm = W - 9 * S, header_mid, 3.2 * S
    marks = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dm = ImageDraw.Draw(marks)
    dm.line((cx - arm, cy - arm, cx + arm, cy + arm), fill=GREY + (255,), width=max(1, round(S * 0.5)))
    dm.line((cx - arm, cy + arm, cx + arm, cy - arm), fill=GREY + (255,), width=max(1, round(S * 0.5)))
    img.alpha_composite(marks)

    # dungeon name + keystone level, centred as one run
    name_mid = (NAME_Y + NAME_H / 2) * S
    lvl = f"  +{level}" if level else ""
    arrow_w = (11 * S) if (level and above) else 0
    w_name, w_lvl = width_of(dungeon, f_name), width_of(lvl, f_name)
    x = (W - (w_name + w_lvl + arrow_w)) / 2
    text(img, (x, name_mid), dungeon, f_name, (255, 255, 255), anchor="lm", offset=S / 4)
    if lvl:
        cursor = x + w_name
        if above:
            mark = up_arrow(round(9 * S), ABOVE)
            img.alpha_composite(mark, (round(cursor + 5 * S), round(name_mid - mark.height / 2)))
            cursor += arrow_w
        text(img, (cursor, name_mid), lvl, f_name, ABOVE if above else GOLD,
             anchor="lm", offset=S / 4)

    # teleport button
    bx0, by0 = EDGE * S, BUTTON_Y * S
    bx1, by1 = (PANEL_W - EDGE) * S, (BUTTON_Y + BUTTON_H) * S
    fill(img, (bx0, by0, bx1, by1), (5, 5, 8, 235))
    frame(img, (bx0, by0, bx1, by1), ACCENT + (90,), max(1, S // 2))

    icon = portal_icon(ICON_SZ * S)
    icon_x = round(bx0 + 8 * S)
    icon_y = round(by0 + (BUTTON_H * S - ICON_SZ * S) / 2)
    img.alpha_composite(icon, (icon_x, icon_y))

    text(img, (icon_x + ICON_SZ * S + 9 * S, by0 + BUTTON_H * S / 2), caption, f_caption,
         (255, 255, 255), anchor="lm", offset=S / 4)

    text(img, (W / 2, (FOOTER_Y + FOOTER_H / 2) * S), footer, f_footer, GREY, anchor="mm",
         offset=S / 4)
    return img



def up_arrow(size, colour):
    """The 'above your best' marker that sits before a keystone level."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(s * 0.5, s * 0.18), (s * 0.92, s * 0.62), (s * 0.66, s * 0.62),
               (s * 0.66, s * 0.86), (s * 0.34, s * 0.86), (s * 0.34, s * 0.62),
               (s * 0.08, s * 0.62)], fill=colour + (255,))
    return img.resize((size, size), Image.LANCZOS)


def avatar_glyph(size, colour):
    """Stand-in for a unit portrait: a class-tinted bust in a circular frame."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, s - 1, s - 1), fill=(18, 22, 30, 255))

    tint = tuple(round(c * 0.55 + 30) for c in colour)
    d.ellipse((s * 0.30, s * 0.20, s * 0.70, s * 0.58), fill=tint + (255,))       # head
    d.ellipse((s * 0.14, s * 0.56, s * 0.86, s * 1.25), fill=tint + (255,))       # shoulders

    ring = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse((1, 1, s - 2, s - 2), outline=colour + (235,),
                                 width=max(2, s // 22))
    img.alpha_composite(ring)

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, s - 1, s - 1), fill=255)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (s, s), 0), mask))
    return img.resize((size, size), Image.LANCZOS)


def dungeon_glyph(size, hue):
    """Stand-in for the challenge-mode map art: a lit archway thumbnail."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    img.alpha_composite(vgradient((s, s), tuple(round(c * 0.55) for c in hue) + (255,),
                                  (6, 8, 12, 255)))
    d = ImageDraw.Draw(img)
    # The arch runs off the bottom edge, so it reads as standing on the floor
    # rather than as a floating capsule.
    d.rounded_rectangle((s * 0.24, s * 0.26, s * 0.76, s * 1.30), radius=s * 0.26,
                        fill=tuple(min(255, round(c * 1.15)) for c in hue) + (255,))
    d.rounded_rectangle((s * 0.34, s * 0.38, s * 0.66, s * 1.30), radius=s * 0.16,
                        fill=(245, 250, 255, 200))
    img.alpha_composite(glow((s, s), (255, 255, 255, 70), s * 0.22), (0, round(s * 0.25)))
    img = img.filter(ImageFilter.GaussianBlur(s * 0.012))
    img = img.resize((size, size), Image.LANCZOS)
    frame(img, (0, 0, size, size), (0, 0, 0, 210), 1)
    return img


# ---------------------------------------------------------------------------
#  The keystone picker, at an integer magnification of the real window.
# ---------------------------------------------------------------------------
def picker(scale=3, rows=None, chosen=1, tab="Party"):
    """rows: (player, colour, dungeon, level, hue, above, score) tuples."""
    rows = rows or []
    S = scale
    W = LIST_W * S
    list_top = HEADER_H + TAB_H + COLHDR_H
    top = list_top + len(rows) * ROW_H
    H = (top + 8 + 22 + 30 + LIST_PAD) * S

    img = Image.new("RGBA", (W, H), (13, 13, 15, 255))
    frame(img, (0, 0, W, H), (0, 0, 0, 255), S)

    header_bottom = S + HEADER_H * S
    fill(img, (S, S, W - S, header_bottom), (0, 0, 0, 115))
    fill(img, (S, header_bottom, W - S, header_bottom + S), ACCENT + (140,))

    f_title = font(UI_FONT, 11 * S)
    f_tab = font(UI_FONT, 11 * S)
    f_col = font(UI_FONT_REG, 9 * S)
    f_row = font(UI_FONT, ROW_FONT * S)
    f_choice = font(UI_FONT, 11 * S)
    f_btn = font(UI_FONT, 11 * S)

    header_mid = S + HEADER_H * S / 2
    text(img, (LIST_PAD * S, header_mid), "Keystones", f_title, ACCENT, anchor="lm", offset=S / 4)

    cx, cy, arm = W - 9 * S, header_mid, 3.2 * S
    marks = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dm = ImageDraw.Draw(marks)
    dm.line((cx - arm, cy - arm, cx + arm, cy + arm), fill=GREY + (255,), width=max(1, round(S * 0.5)))
    dm.line((cx - arm, cy + arm, cx + arm, cy - arm), fill=GREY + (255,), width=max(1, round(S * 0.5)))
    img.alpha_composite(marks)

    # tabs
    tab_y = (HEADER_H + 1) * S
    tab_x = (LIST_PAD - 2) * S
    for name in ("Party", "Guild"):
        tw = max(52 * S, width_of(name, f_tab) + 22 * S)
        active = (name == tab)
        text(img, (tab_x + tw / 2, tab_y + TAB_H * S / 2), name, f_tab,
             ACCENT if active else (158, 168, 184), anchor="mm", offset=S / 4)
        if active:
            fill(img, (tab_x + 4 * S, tab_y + TAB_H * S - 2 * S, tab_x + tw - 4 * S,
                       tab_y + TAB_H * S), ACCENT + (255,))
        tab_x += tw + 2 * S

    # column titles
    x0, x1 = LIST_PAD * S, (LIST_W - LIST_PAD) * S
    x_name = x0 + (3 + AVATAR_SZ + 5) * S
    x_icon = x_name + (NAME_W + 4) * S
    x_dungeon = x_icon + (DUNGEON_SZ + 4) * S
    right_score = x1 - 4 * S

    col_y = (HEADER_H + TAB_H + 2) * S
    text(img, (x0 + 3 * S, col_y), "PLAYER", f_col, (115, 128, 143), offset=S / 4)
    text(img, (x_icon, col_y), "KEYSTONE", f_col, (115, 128, 143), offset=S / 4)
    text(img, (right_score, col_y), "SCORE", f_col, (115, 128, 143), anchor="ra", offset=S / 4)

    for i, (player, colour, dungeon, level, hue, above, score) in enumerate(rows):
        y0 = (list_top + i * ROW_H) * S
        y1 = y0 + (ROW_H - 2) * S
        selected = (i == chosen)
        fill(img, (x0, y0, x1, y1), (255, 255, 255, 26 if selected else 10))
        if selected:
            frame(img, (x0, y0, x1, y1), ACCENT + (230,), S)
            fill(img, (x0, y0, x0 + 2 * S, y1), ACCENT + (230,))

        mid = (y0 + y1) / 2
        keyed = level > 0

        av = avatar_glyph(AVATAR_SZ * S, colour)
        img.alpha_composite(av, (round(x0 + 3 * S), round(mid - av.height / 2)))
        text(img, (x_name, mid), player, f_row, colour, anchor="lm", offset=S / 4)

        if keyed:
            dg = dungeon_glyph(DUNGEON_SZ * S, hue)
            img.alpha_composite(dg, (round(x_icon), round(mid - dg.height / 2)))
        text(img, (x_dungeon, mid), dungeon, f_row,
             (235, 240, 245) if keyed else (115, 120, 128), anchor="lm", offset=S / 4)

        if keyed:
            cursor = x_dungeon + width_of(dungeon, f_row) + 7 * S
            if above:
                mark = up_arrow(round(9 * S), ABOVE)
                img.alpha_composite(mark, (round(cursor), round(mid - mark.height / 2)))
                cursor += mark.width + 2 * S
            text(img, (cursor, mid), "+%d" % level, f_row, ABOVE if above else GOLD,
                 anchor="lm", offset=S / 4)

        if score:
            text(img, (right_score, mid), str(score), f_row, (176, 140, 224),
                 anchor="rm", offset=S / 4)

    # selection line
    choice_y = (top + 10) * S
    chosen_row = rows[chosen] if 0 <= chosen < len(rows) else None
    if chosen_row:
        lvl_colour = ABOVE if chosen_row[5] else GOLD
        parts = [(chosen_row[2] + " ", (235, 240, 245)),
                 ("+%d" % chosen_row[3], lvl_colour), ("  (", (170, 178, 188)),
                 (chosen_row[0], ACCENT), (")", (170, 178, 188))]
        total = sum(width_of(t, f_choice) for t, _ in parts)
        x = (W - total) / 2
        for t, colour in parts:
            text(img, (x, choice_y), t, f_choice, colour, offset=S / 4)
            x += width_of(t, f_choice)

    # buttons along the bottom
    btn_h = 22 * S
    btn_y = H - LIST_PAD * S - btn_h
    ref_w = 78 * S
    send_w = W - LIST_PAD * S * 2 - 14 * S - ref_w - 6 * S
    fill(img, (LIST_PAD * S, btn_y, LIST_PAD * S + send_w, btn_y + btn_h), (20, 23, 28, 242))
    frame(img, (LIST_PAD * S, btn_y, LIST_PAD * S + send_w, btn_y + btn_h),
          ACCENT + (90,), max(1, S // 2))
    text(img, (LIST_PAD * S + send_w / 2, btn_y + btn_h / 2), "Send to Party", f_btn,
         (255, 255, 255), anchor="mm", offset=S / 4)

    ref_x = W - (LIST_PAD + 14) * S - ref_w
    fill(img, (ref_x, btn_y, ref_x + ref_w, btn_y + btn_h), (20, 23, 28, 242))
    frame(img, (ref_x, btn_y, ref_x + ref_w, btn_y + btn_h), ACCENT + (90,), max(1, S // 2))
    text(img, (ref_x + ref_w / 2, btn_y + btn_h / 2), "Refresh", f_btn,
         (215, 222, 230), anchor="mm", offset=S / 4)

    # resize grip
    grip = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dg2 = ImageDraw.Draw(grip)
    gx, gy = W - 4 * S, H - 4 * S
    for k, step in enumerate((3, 7, 11)):
        dg2.line((gx - step * S, gy, gx, gy - step * S),
                 fill=(150, 160, 175, 200 - k * 40), width=max(1, round(S * 0.6)))
    img.alpha_composite(grip)
    return img


# (player, class colour, dungeon, keystone level, dungeon-art hue,
#  above the viewer's season best, mythic+ score)
PARTY_ROWS = [
    ("Camyana", (199, 156, 110), "Murder Row", 14, (150, 60, 70), False, 3212),
    ("Bobbo",   (105, 204, 240), "Kings' Rest", 12, (190, 150, 70), True, 3184),
    ("Cira",    (255, 125, 10),  "Blinding Vale", 8, (70, 130, 120), True, 2760),
    ("Thessa",  (255, 244, 104), "Ruby Life Pools", 7, (170, 70, 60), False, 2455),
    ("Marn",    (170, 211, 114), "no keystone", 0, None, False, 1980),
]


# ---------------------------------------------------------------------------
#  Assets
# ---------------------------------------------------------------------------
def build_popup():
    img = popup()
    os.makedirs(FULL, exist_ok=True)
    img.save(os.path.join(FULL, "keyport-popup@4x.png"))
    # 3x (660px) sits comfortably inside the description column
    small = popup(scale=3)
    small.save(os.path.join(OUT, "keyport-popup.png"))
    return img


def build_picker():
    img = picker(rows=PARTY_ROWS, chosen=1)
    os.makedirs(FULL, exist_ok=True)
    img.save(os.path.join(FULL, "keyport-picker@3x.png"))
    body = img.resize((round(img.width * 2 / 3), round(img.height * 2 / 3)), Image.LANCZOS)
    body.save(os.path.join(OUT, "keyport-picker.png"))
    return img


def build_gallery_picker(picker_img, _unused=None):
    W, H = 1280, 720
    canvas = backdrop((W, H))

    text(canvas, (W / 2, 76), "Every key in the group, one click away",
         font(BODY_FONT_BOLD, 38), (238, 245, 252), anchor="mm", offset=2)
    text(canvas, (W / 2, 124),
         "/kp lists what the party is holding. Pick one, send it to everyone.",
         font(BODY_FONT, 22), (152, 172, 192), anchor="mm", offset=1)

    shot = picker_img.resize((round(picker_img.width * 0.52), round(picker_img.height * 0.52)),
                             Image.LANCZOS)
    place(canvas, shot, (96, 202), blur=24, alpha=200)

    # The popup has to agree with the row that is selected in the picker.
    chosen = PARTY_ROWS[1]
    sent_popup = popup(dungeon=chosen[2], level=chosen[3], above=chosen[5],
                       footer=chosen[0] + "'s key, sent to your party")
    small = sent_popup.resize((round(sent_popup.width * 0.45), round(sent_popup.height * 0.45)),
                              Image.LANCZOS)
    popup_x, popup_y = 830, 286
    place(canvas, small, (popup_x, popup_y), blur=24, alpha=200)

    arrow_y = popup_y + small.height / 2
    bar = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    da = ImageDraw.Draw(bar)
    da.line((730, arrow_y, 780, arrow_y), fill=ACCENT + (225,), width=4)
    da.polygon([(780, arrow_y - 13), (812, arrow_y), (780, arrow_y + 13)], fill=ACCENT + (225,))
    canvas.alpha_composite(bar)

    text(canvas, (popup_x + small.width / 2, popup_y + small.height + 30),
         "on everyone's screen, owner named",
         font(BODY_FONT, 19), (150, 170, 190), anchor="mm", offset=1)
    text(canvas, (W / 2, H - 78),
         "Green means the key is above your own best for that dungeon.",
         font(BODY_FONT, 21), (120, 210, 150), anchor="mm", offset=1)
    text(canvas, (W / 2, H - 44),
         "Keys come from LibKeystone, so party members running DBM or BigWigs show up too.",
         font(BODY_FONT, 20), (152, 172, 192), anchor="mm", offset=1)

    save_pair(canvas, "keyport-gallery-picker.png")


def build_icon():
    src = os.path.join(RAW, "icon-portal.png")
    if not os.path.exists(src):
        print("  ! raw/icon-portal.png missing, skipping avatar")
        return None
    art = Image.open(src).convert("RGBA")
    # Crop in past the outer rune ring: at CurseForge's 64px listing size the
    # full emblem turns to mush, the crystal and vortex still read.
    side = round(min(art.size) * 0.78)
    art = art.crop(((art.width - side) // 2, (art.height - side) // 2,
                    (art.width + side) // 2, (art.height + side) // 2))
    art = art.resize((400, 400), Image.LANCZOS)
    art = ImageEnhance.Contrast(art).enhance(1.12)
    art = ImageEnhance.Color(art).enhance(1.08)

    # vignette so the emblem reads on light and dark CurseForge backdrops
    vig = Image.new("L", (400, 400), 0)
    ImageDraw.Draw(vig).ellipse((-60, -60, 460, 460), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(60))
    art = Image.composite(art, Image.new("RGBA", (400, 400), (2, 4, 8, 255)), vig)

    art.save(os.path.join(OUT, "keyport-icon-400.png"))
    art.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, "keyport-icon-64.png"))
    return art


def build_banner(popup_img):
    W, H = 1280, 640
    src = os.path.join(RAW, "banner-portal.png")
    if os.path.exists(src):
        art = Image.open(src).convert("RGBA")
        ratio = max(W / art.width, H / art.height)
        art = art.resize((round(art.width * ratio), round(art.height * ratio)), Image.LANCZOS)
        canvas = art.crop((art.width - W, max(0, (art.height - H) // 2),
                           art.width, max(0, (art.height - H) // 2) + H))
    else:
        print("  ! raw/banner-portal.png missing, using a flat backdrop")
        canvas = Image.new("RGBA", (W, H), INK + (255,))
        canvas.alpha_composite(glow((W, H), (30, 90, 160, 90), W * 0.3))

    # scrim: opaque at the left, clear by ~72% across, so type stays legible
    scrim = Image.new("RGBA", (W, H), (4, 6, 11, 255))
    ramp = Image.new("L", (W, 1))
    rpx = ramp.load()
    for x in range(W):
        rpx[x, 0] = round(242 * max(0.0, 1 - (x / (W - 1) / 0.72) ** 1.7))
    scrim.putalpha(ramp.resize((W, H)))
    canvas.alpha_composite(scrim)

    f_mark = font(DISPLAY_FONT, 92)
    f_tag = font(BODY_FONT, 29)
    f_cmd = font(MONO_FONT_BOLD, 34)

    x0, y0 = 80, 158
    canvas.alpha_composite(glow((820, 340), (35, 110, 190, 65), 230), (x0 - 200, y0 - 70))
    text(canvas, (x0, y0), "KeyPort", f_mark, (240, 250, 255), offset=3)
    fill(canvas, (x0 + 4, y0 + 128, x0 + 96, y0 + 132), ACCENT + (255,))
    text(canvas, (x0, y0 + 164), "One command. The whole group", f_tag, (198, 216, 232), offset=2)
    text(canvas, (x0, y0 + 204), "gets the dungeon teleport.", f_tag, (198, 216, 232), offset=2)

    cw = width_of("/kp KR 10", f_cmd)
    cx, cy = x0, y0 + 274
    plate = Image.new("RGBA", (round(cw) + 40, 62), (6, 10, 18, 228))
    frame(plate, (0, 0, plate.width, plate.height), ACCENT + (110,), 2)
    canvas.alpha_composite(plate, (cx - 16, cy - 13))
    text(canvas, (cx, cy), "/kp ", f_cmd, ACCENT, offset=2)
    text(canvas, (cx + width_of("/kp ", f_cmd), cy), "KR 10", f_cmd, (255, 255, 255), offset=2)

    small = popup_img.resize((popup_img.width // 2, popup_img.height // 2), Image.LANCZOS)
    plate = shadowed(small, blur=24, alpha=195)
    canvas.alpha_composite(plate, (W - plate.width - 92, (H - plate.height) // 2))

    save_pair(canvas, "keyport-banner.png")
    return canvas


def chat_plate(rows, width, pad=26, title=None):
    """A chat-frame style panel.

    Row kinds:
        ("cmd",    "/kp KR 10")        typed command, monospace
        ("desc",   "by short code")    caption under a command
        ("accent", "text")             accent-coloured line
        ("kv",     "KR", "Kings' Rest") aligned code/name columns
        ("gap",    12)                 vertical space
    """
    f_line = font(BODY_FONT, 22)
    f_cmd = font(MONO_FONT_BOLD, 24)
    f_code = font(MONO_FONT_BOLD, 22)
    f_title = font(BODY_FONT_BOLD, 16)
    line_h, col = 34, 92

    height = pad * 2 + (34 if title else 0)
    for row in rows:
        height += row[1] if row[0] == "gap" else line_h

    plate = Image.new("RGBA", (width, round(height)), (7, 9, 14, 236))
    frame(plate, (0, 0, width, height), (0, 0, 0, 255), 2)
    fill(plate, (2, 2, width - 2, 4), ACCENT + (130,))

    y = pad
    if title:
        text(plate, (pad, y), title, f_title, (118, 138, 158), offset=1)
        y += 34
    for row in rows:
        kind = row[0]
        if kind == "gap":
            y += row[1]
            continue
        if kind == "cmd":
            text(plate, (pad, y), row[1], f_cmd, (255, 255, 255), offset=1)
        elif kind == "desc":
            text(plate, (pad + 4, y), row[1], f_line, (146, 158, 172), offset=1)
        elif kind == "accent":
            text(plate, (pad, y), row[1], f_line, ACCENT, offset=1)
        elif kind == "kv":
            text(plate, (pad + 8, y), row[1], f_code, ACCENT, offset=1)
            text(plate, (pad + col, y), row[2], f_line, (198, 206, 216), offset=1)
        else:
            text(plate, (pad, y), row[1], f_line, (190, 198, 208), offset=1)
        y += line_h
    return plate


def place(canvas, panel_img, xy, blur=22, alpha=185):
    """Composite a panel with a drop shadow so its visible corner lands on xy."""
    padded = shadowed(panel_img, blur=blur, alpha=alpha)
    pad = blur * 3
    canvas.alpha_composite(padded, (round(xy[0]) - pad, round(xy[1]) - pad))


def backdrop(size):
    W, H = size
    src = os.path.join(RAW, "banner-portal.png")
    if os.path.exists(src):
        art = Image.open(src).convert("RGBA")
        ratio = max(W / art.width, H / art.height)
        art = art.resize((round(art.width * ratio), round(art.height * ratio)), Image.LANCZOS)
        canvas = art.crop((0, 0, W, H)).filter(ImageFilter.GaussianBlur(10))
        canvas.alpha_composite(Image.new("RGBA", (W, H), (4, 6, 11, 180)))
        return canvas
    canvas = Image.new("RGBA", (W, H), INK + (255,))
    canvas.alpha_composite(glow((W, H), (30, 90, 160, 90), W * 0.35))
    return canvas


def build_gallery_command(popup_img):
    W, H = 1280, 720
    canvas = backdrop((W, H))

    text(canvas, (W / 2, 76), "One command. Everyone gets the teleport.",
         font(BODY_FONT_BOLD, 38), (238, 245, 252), anchor="mm", offset=2)
    text(canvas, (W / 2, 124), "Built for premade keys, where Group Finder never fires a reminder.",
         font(BODY_FONT, 22), (152, 172, 192), anchor="mm", offset=1)

    # popup on the right, sized so it and its shadow stay inside the frame
    small = popup_img.resize((round(popup_img.width * 0.58), round(popup_img.height * 0.58)),
                             Image.LANCZOS)
    popup_x, popup_y = 700, 250
    place(canvas, small, (popup_x, popup_y), blur=26, alpha=205)
    centre_y = popup_y + small.height / 2

    plate = chat_plate([("cmd", "/kp kr 10"),
                        ("desc", "dungeon code + keystone level")], 420, title="YOU TYPE")
    place(canvas, plate, (92, centre_y - plate.height / 2), blur=20, alpha=175)

    arrow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    da = ImageDraw.Draw(arrow)
    da.line((556, centre_y, 646, centre_y), fill=ACCENT + (225,), width=4)
    da.polygon([(646, centre_y - 13), (680, centre_y), (646, centre_y + 13)], fill=ACCENT + (225,))
    canvas.alpha_composite(arrow)
    text(canvas, (614, centre_y - 36), "party-wide", font(BODY_FONT, 19), (135, 165, 190),
         anchor="mm", offset=1)

    text(canvas, (W / 2, H - 56),
         "One line in party chat for everyone else, and one click to teleport.",
         font(BODY_FONT, 21), (152, 172, 192), anchor="mm", offset=1)

    save_pair(canvas, "keyport-gallery-command.png")


def build_gallery_codes():
    W, H = 1280, 720
    canvas = backdrop((W, H))

    text(canvas, (W / 2, 76), "Codes you never have to learn",
         font(BODY_FONT_BOLD, 38), (238, 245, 252), anchor="mm", offset=2)
    text(canvas, (W / 2, 124),
         "Generated from your client's own dungeon names. Every language, every season.",
         font(BODY_FONT, 22), (152, 172, 192), anchor="mm", offset=1)

    left = chat_plate([
        ("accent", "KeyPort   this season:"),
        ("kv", "BV", "The Blinding Vale"),
        ("kv", "VA", "Voidscar Arena"),
        ("kv", "DoN", "Den of Nalorakk"),
        ("kv", "MR", "Murder Row"),
        ("kv", "AoF", "Altar of Fangs"),
        ("kv", "RLP", "Ruby Life Pools"),
        ("kv", "ToS", "Temple of Sethraliss"),
        ("kv", "KR", "Kings' Rest"),
    ], 512, title="/KP LIST")
    place(canvas, left, (84, 202), blur=20, alpha=175)

    right = chat_plate([
        ("cmd", "/kp kr 10"),
        ("desc", "short code + keystone level"),
        ("gap", 14),
        ("cmd", "/kp kings rest 12"),
        ("desc", "name (or part of it) + level"),
        ("gap", 14),
        ("cmd", "/kp kr10"),
        ("desc", "level glued to the code"),
        ("gap", 14),
        ("cmd", "/kp mine"),
        ("desc", "uses the key in your bags"),
    ], 512, title="ALL OF THESE WORK")
    place(canvas, right, (684, 202), blur=20, alpha=175)

    text(canvas, (W / 2, H - 56),
         "/kp list all   /kp me   /kp hide   /kp announce   /kp scale   /kp map",
         font(MONO_FONT, 21), (135, 165, 190), anchor="mm", offset=1)

    save_pair(canvas, "keyport-gallery-codes.png")


if __name__ == "__main__":
    print("popup    ...")
    pop = build_popup()
    print("avatar   ...")
    build_icon()
    print("banner   ...")
    build_banner(pop)
    print("picker   ...")
    pick = build_picker()
    print("gallery  ...")
    build_gallery_command(pop)
    build_gallery_picker(pick)
    build_gallery_codes()
    print("done ->", OUT)
