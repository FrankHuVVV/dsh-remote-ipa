"""Generate the iOS app icon set from one 1024px master.

Brand: solid #2F6BFF square with white "DSH" wordmark. iOS applies the corner
mask itself, so the source image stays square and fully opaque (App Store
rejects icons with alpha).
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ICON_DIR = Path(__file__).resolve().parents[1] / "app" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

BLUE = (47, 107, 255, 255)
WHITE = (255, 255, 255, 255)

# filename -> pixel size
TARGETS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\seguiemj.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def build_master() -> Image.Image:
    size = 1024
    image = Image.new("RGB", (size, size), BLUE[:3])
    draw = ImageDraw.Draw(image)

    font = load_font(300)
    text = "DSH"
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    width, height = right - left, bottom - top
    draw.text(
        ((size - width) / 2 - left, (size - height) / 2 - top - 18),
        text,
        font=font,
        fill=WHITE[:3],
    )

    # A thin baseline bar: reads as "connected" even at 20px.
    bar_width = 380
    bar_height = 26
    x0 = (size - bar_width) / 2
    y0 = size * 0.72
    draw.rounded_rectangle(
        [x0, y0, x0 + bar_width, y0 + bar_height],
        radius=bar_height / 2,
        fill=WHITE[:3],
    )
    return image


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    master = build_master()
    master.save(ICON_DIR / "Icon-App-1024x1024@1x.png", format="PNG")
    for name, size in TARGETS.items():
        if size == 1024:
            continue
        resized = master.resize((size, size), Image.LANCZOS)
        resized.save(ICON_DIR / name, format="PNG")
    print(f"wrote {len(TARGETS)} icons to {ICON_DIR}")


if __name__ == "__main__":
    main()
