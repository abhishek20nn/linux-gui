import os
from PIL import Image, ImageDraw, ImageFont

def render_icon(size):
    # Render at 4x for clean supersampling
    scale = 4
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = int(6 * (canvas_size / 128.0))
    corner_r = int(28 * (canvas_size / 128.0))
    
    # Red background squircle
    draw.rounded_rectangle(
        [pad, pad, canvas_size - pad, canvas_size - pad],
        radius=corner_r,
        fill=(220, 20, 20, 255)
    )

    # Smartphone frame
    phone_x1 = int(28 * (canvas_size / 128.0))
    phone_y1 = int(18 * (canvas_size / 128.0))
    phone_x2 = int(100 * (canvas_size / 128.0))
    phone_y2 = int(110 * (canvas_size / 128.0))
    phone_r = int(10 * (canvas_size / 128.0))
    border_w = max(2, int(4 * (canvas_size / 128.0)))

    draw.rounded_rectangle(
        [phone_x1, phone_y1, phone_x2, phone_y2],
        radius=phone_r,
        fill=(18, 18, 18, 255),
        outline=(255, 255, 255, 255),
        width=border_w
    )

    # Play button triangle in center of phone
    poly_cx = (phone_x1 + phone_x2) // 2
    poly_cy = (phone_y1 + phone_y2) // 2 - int(4 * (canvas_size / 128.0))
    poly_w = int(16 * (canvas_size / 128.0))
    poly_h = int(18 * (canvas_size / 128.0))

    tri_p1 = (poly_cx - poly_w // 2, poly_cy - poly_h // 2)
    tri_p2 = (poly_cx - poly_w // 2, poly_cy + poly_h // 2)
    tri_p3 = (poly_cx + poly_w // 2, poly_cy)

    draw.polygon([tri_p1, tri_p2, tri_p3], fill=(255, 255, 255, 255))

    # Downscale with Lanczos filter for crisp anti-aliasing
    final_img = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

os.makedirs("icons", exist_ok=True)
for s in [16, 32, 48, 128]:
    out_path = os.path.join("icons", f"icon-{s}.png")
    icon = render_icon(s)
    icon.save(out_path, format="PNG")
    print(f"Generated {out_path} ({s}x{s})")

print("All icons generated successfully.")
