from PIL import Image, ImageDraw, ImageFont
import os

def add_text_to_image(input_path, output_path, text, font_path="mods/apis/sl_gui/fonts/regular.ttf"):
    try:
        img = Image.open(input_path).convert("RGBA")
        # Resize to standard if needed, e.g., 256x256
        if img.size != (256, 256):
            img = img.resize((256, 256), Image.Resampling.LANCZOS)
            
        draw = ImageDraw.Draw(img)
        
        # Try to load font
        font_size = 64
        try:
            font = ImageFont.truetype(font_path, font_size)
        except:
            font = ImageFont.load_default()
            
        # Position at bottom right
        # Use textbbox to get dimensions
        bbox = draw.textbbox((0, 0), text, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        
        margin = 10
        x = img.width - w - margin
        y = img.height - h - margin - 15 # offset for descenders
        
        # Draw background shadow for text
        draw.text((x+2, y+2), text, font=font, fill=(0, 0, 0, 255))
        # Draw neon text
        draw.text((x, y), text, font=font, fill=(0, 255, 255, 255))
        
        img.save(output_path)
    except Exception as e:
        print(f"Error processing {input_path}: {e}")

# Depth Achievements
depths = {
    "1k": "1000",
    "5k": "5000",
    "10k": "10k",
    "20k": "20k"
}
for suffix, label in depths.items():
    add_text_to_image("mods/apis/sl_gui/textures/achievement_abyss_base.png", 
                      f"mods/apis/sl_gui/textures/achievement_depth_{suffix}.png", 
                      label)

# Fall Achievements
falls = {
    "100": "100",
    "1k": "1k",
    "10k": "10k"
}
for suffix, label in falls.items():
    add_text_to_image("mods/apis/sl_gui/textures/achievement_fall_base.png", 
                      f"mods/apis/sl_gui/textures/achievement_fall_{suffix}.png", 
                      label)
