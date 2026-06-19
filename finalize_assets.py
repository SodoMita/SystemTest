from PIL import Image, ImageDraw, ImageFont
import os

def add_text_to_image(input_path, output_path, text, font_path="mods/apis/sl_gui/fonts/regular.ttf"):
    try:
        img = Image.open(input_path).convert("RGBA")
        if img.size != (256, 256):
            img = img.resize((256, 256), Image.Resampling.LANCZOS)
        draw = ImageDraw.Draw(img)
        font_size = 80
        try:
            font = ImageFont.truetype(font_path, font_size)
        except:
            font = ImageFont.load_default()
        bbox = draw.textbbox((0, 0), text, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        x = img.width - w - 10
        y = img.height - h - 25
        draw.text((x+3, y+3), text, font=font, fill=(0, 0, 0, 255))
        draw.text((x, y), text, font=font, fill=(0, 255, 255, 255))
        img.save(output_path)
    except Exception as e:
        print(f"Error numbering {input_path}: {e}")

def draw_neon_loop(output_path):
    img = Image.new('RGBA', (256, 256), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    # Draw a looping arrow
    draw.arc([40, 40, 216, 216], start=0, end=270, fill=(0, 255, 255, 255), width=8)
    draw.polygon([(216, 128), (206, 108), (226, 108)], fill=(0, 255, 255, 255))
    # Small character
    draw.rectangle([118, 110, 138, 146], outline=(255, 255, 255, 255), width=3)
    img.save(output_path)

def draw_loop_land(output_path):
    img = Image.new('RGBA', (256, 256), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    # Platform
    draw.rectangle([40, 200, 216, 220], fill=(0, 255, 0, 255))
    # Character landing
    draw.rectangle([118, 160, 138, 196], outline=(255, 255, 255, 255), width=3)
    # Speed lines
    draw.line([128, 40, 128, 150], fill=(255, 255, 255, 100), width=2)
    img.save(output_path)

def draw_cube_egg(output_path):
    img = Image.new('RGBA', (256, 256), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    # Isometric-ish cube
    color = (255, 0, 255, 255) # Magenta
    draw.polygon([(128, 60), (200, 100), (128, 140), (56, 100)], outline=color, width=4) # Top
    draw.polygon([(56, 100), (128, 140), (128, 220), (56, 180)], outline=color, width=4) # Left
    draw.polygon([(200, 100), (128, 140), (128, 220), (200, 180)], outline=color, width=4) # Right
    # Circuit patterns
    draw.line([100, 120, 80, 140], fill=color, width=2)
    draw.line([156, 120, 176, 140], fill=color, width=2)
    img.save(output_path)

# Process
depths = {"1k": "1000", "5k": "5000", "10k": "10k", "20k": "20k"}
for s, l in depths.items():
    add_text_to_image("mods/apis/sl_gui/textures/achievement_abyss_base.png", 
                      f"mods/apis/sl_gui/textures/achievement_depth_{s}.png", l)

falls = {"100": "100", "1k": "1k", "10k": "10k"}
for s, l in falls.items():
    add_text_to_image("mods/apis/sl_gui/textures/achievement_fall_base.png", 
                      f"mods/apis/sl_gui/textures/achievement_fall_{s}.png", l)

draw_neon_loop("mods/apis/sl_gui/textures/achievement_up_is_down.png")
draw_loop_land("mods/apis/sl_gui/textures/achievement_loop_land.png")
draw_cube_egg("mods/apis/sl_gui/textures/achievement_easter_egg.png")

# Use Abyss Base for the 1k Abyss achievement itself if needed, or draw it
# Actually the loop already does achievement_depth_1k.png which is "Into the Abyss"
