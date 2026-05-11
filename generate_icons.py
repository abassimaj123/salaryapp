"""
SalaryApp Icon Generator — CA / US / UK
Inspired by MortgageCA/US/UK style: clean, simple, professional
"""
from PIL import Image, ImageDraw
import os, math

# ── Flavor configs ────────────────────────────────────────────────
FLAVORS = {
    "ca": {
        "bg":      (230, 126,  34),   # Burnt Orange #E67E22
        "calc_bg": (255, 255, 255),   # White calculator
        "disp":    (239,  68,  68),   # Red display
        "badge_bg":(239,  68,  68),   # Red badge circle
        "badge_fg":(255, 255, 255),   # White badge symbol
        "symbol":  "leaf",            # Maple leaf
        "label":   "CA",
    },
    "us": {
        "bg":      (220,  38,  38),   # Confident Red #DC2626
        "calc_bg": (255, 255, 255),
        "disp":    (220,  38,  38),
        "badge_bg":(255, 255, 255),
        "badge_fg":(220,  38,  38),
        "symbol":  "$",
        "label":   "US",
    },
    "uk": {
        "bg":      ( 31,  41,  55),   # Premium Black #1F2937
        "calc_bg": (255, 255, 255),
        "disp":    ( 31,  41,  55),
        "badge_bg":(212, 175,  55),   # Gold #D4AF37
        "badge_fg":( 31,  41,  55),
        "symbol":  "£",
        "label":   "UK",
    },
}

# ── Size map: (folder, size, is_foreground) ──────────────────────
SIZES = {
    "mipmap-mdpi":        48,
    "mipmap-hdpi":        72,
    "mipmap-xhdpi":       96,
    "mipmap-xxhdpi":     144,
    "mipmap-xxxhdpi":    192,
    "drawable-mdpi":     108,
    "drawable-hdpi":     162,
    "drawable-xhdpi":    216,
    "drawable-xxhdpi":   324,
    "drawable-xxxhdpi":  432,
}

BASE = "android/app/src"

# ── Draw maple leaf ───────────────────────────────────────────────
def draw_maple_leaf(draw, cx, cy, size, color):
    """Simplified 7-point maple leaf"""
    s = size * 0.42
    pts = []
    # Build leaf polygon (simplified)
    leaf_pts = [
        (cx,      cy - s),
        (cx+s*0.3, cy-s*0.5),
        (cx+s*0.7, cy-s*0.6),
        (cx+s*0.4, cy-s*0.1),
        (cx+s*0.9, cy+s*0.1),
        (cx+s*0.4, cy+s*0.1),
        (cx+s*0.3, cy+s*0.6),
        (cx,       cy+s*0.3),
        (cx-s*0.3, cy+s*0.6),
        (cx-s*0.4, cy+s*0.1),
        (cx-s*0.9, cy+s*0.1),
        (cx-s*0.4, cy-s*0.1),
        (cx-s*0.7, cy-s*0.6),
        (cx-s*0.3, cy-s*0.5),
    ]
    draw.polygon(leaf_pts, fill=color)
    # Stem
    stem_w = max(2, int(size * 0.06))
    draw.rectangle([cx - stem_w//2, cy + int(s*0.3),
                    cx + stem_w//2, cy + int(s*0.6)], fill=color)

# ── Draw calculator body ──────────────────────────────────────────
def draw_calculator(draw, x, y, w, h, bg_color, disp_color, btn_color):
    r = max(4, w // 8)
    # Body
    draw.rounded_rectangle([x, y, x+w, y+h], radius=r, fill=bg_color)
    # Display
    dp = max(3, w // 12)
    dh = int(h * 0.28)
    draw.rounded_rectangle([x+dp, y+dp, x+w-dp, y+dp+dh],
                            radius=max(2, r//2), fill=disp_color)
    # Buttons — 3x2 grid
    btn_r = max(2, w // 18)
    bw = (w - dp*2) // 3
    bh = (h - dp*3 - dh) // 2
    for row in range(2):
        for col in range(3):
            bx = x + dp + col * bw + bw//2
            by = y + dp*2 + dh + row * bh + bh//2
            br = btn_r
            draw.ellipse([bx-br, by-br, bx+br, by+br], fill=btn_color)

# ── Draw badge circle ─────────────────────────────────────────────
def draw_badge(draw, cx, cy, r, bg, fg, symbol):
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=bg)
    if symbol == "leaf":
        draw_maple_leaf(draw, cx, cy - r*0.05, r*1.8, fg)
    else:
        # Text symbol: $ or £ — drawn as simple lines
        font_size = int(r * 1.1)
        # Manual text approximation using draw (no font needed)
        try:
            from PIL import ImageFont
            try:
                font = ImageFont.truetype("arial.ttf", font_size)
            except Exception:
                font = ImageFont.load_default()
            bbox = font.getbbox(symbol)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            draw.text((cx - tw//2, cy - th//2 - bbox[1]//2),
                      symbol, fill=fg, font=font)
        except Exception:
            # Fallback: simple line indicator
            draw.line([cx-r*0.4, cy, cx+r*0.4, cy], fill=fg, width=max(2,r//4))

# ── Generate one icon ─────────────────────────────────────────────
def gen_icon(size, flavor_cfg, is_foreground):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if is_foreground:
        # Foreground: icon on transparent bg, safe zone = 66% of total
        pad = int(size * 0.17)
        inner = size - pad * 2
        calc_w = int(inner * 0.68)
        calc_h = int(inner * 0.80)
        cx = pad + (inner - calc_w) // 2
        cy = pad + (inner - calc_h) // 2 - int(inner * 0.03)
    else:
        # Full launcher icon: colored bg + calculator
        r_bg = max(6, size // 8)
        draw.rounded_rectangle([0, 0, size-1, size-1], radius=r_bg,
                                fill=flavor_cfg["bg"])
        pad = int(size * 0.12)
        inner = size - pad * 2
        calc_w = int(inner * 0.68)
        calc_h = int(inner * 0.80)
        cx = pad + (inner - calc_w) // 2
        cy = pad + (inner - calc_h) // 2 - int(inner * 0.03)

    # Calculate button color (slightly transparent bg color)
    b = flavor_cfg["bg"]
    btn_color = (min(255, b[0]+60), min(255, b[1]+60), min(255, b[2]+60), 180) \
                if is_foreground else \
                (max(0, b[0]-20), max(0, b[1]-20), max(0, b[2]-20))

    draw_calculator(draw, cx, cy, calc_w, calc_h,
                    flavor_cfg["calc_bg"],
                    flavor_cfg["disp"],
                    flavor_cfg["disp"] if is_foreground else btn_color)

    # Badge
    badge_r = max(4, int(calc_w * 0.27))
    bx = cx + calc_w - badge_r // 2
    by = cy + calc_h - badge_r // 2
    draw_badge(draw, bx, by, badge_r,
               flavor_cfg["badge_bg"], flavor_cfg["badge_fg"],
               flavor_cfg["symbol"])

    return img

# ── Main ──────────────────────────────────────────────────────────
def main():
    for flavor, cfg in FLAVORS.items():
        print(f"\nGenerating {flavor.upper()} icons...")
        for folder, size in SIZES.items():
            is_fg = folder.startswith("drawable")
            out_dir = os.path.join(BASE, flavor, "res", folder)
            os.makedirs(out_dir, exist_ok=True)

            img = gen_icon(size, cfg, is_fg)

            filename = "ic_launcher_foreground.png" if is_fg else "ic_launcher.png"
            path = os.path.join(out_dir, filename)
            img.save(path, "PNG", optimize=True)

            # Also save ic_launcher_round.png for mipmap folders
            if not is_fg:
                round_path = os.path.join(out_dir, "ic_launcher_round.png")
                # Circular version
                mask = Image.new("L", (size, size), 0)
                mask_draw = ImageDraw.Draw(mask)
                mask_draw.ellipse([0, 0, size-1, size-1], fill=255)
                img_copy = img.copy()
                img_copy.putalpha(mask)
                img_copy.save(round_path, "PNG", optimize=True)

            print(f"  OK {folder}/{filename} ({size}x{size})")

    print("\nAll icons generated!")

if __name__ == "__main__":
    main()
