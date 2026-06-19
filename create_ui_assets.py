from PIL import Image, ImageDraw, ImageFont

def create_category_button(text, filename, size=(256, 64), color=(0, 255, 255)):
    # Create image with transparency
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Dark grey background with some transparency
    bg_color = (30, 30, 30, 240)
    draw.rectangle([0, 0, size[0]-1, size[1]-1], fill=bg_color)
    
    # Outer Glow / Neon Border
    glow_color = (*color, 100)
    for i in range(3):
        draw.rectangle([i, i, size[0]-1-i, size[1]-1-i], outline=glow_color)
        
    # Main Accent Border (bottom)
    draw.rectangle([0, size[1]-4, size[0]-1, size[1]-1], fill=(*color, 255))
    
    # Corner details
    corner_size = 10
    draw.line([0, 0, corner_size, 0], fill=(*color, 255), width=2)
    draw.line([0, 0, 0, corner_size], fill=(*color, 255), width=2)
    
    draw.line([size[0]-1, 0, size[0]-1-corner_size, 0], fill=(*color, 255), width=2)
    draw.line([size[0]-1, 0, size[0]-1, corner_size], fill=(*color, 255), width=2)

    img.save(filename)

# Generate buttons for all categories to ensure consistency
categories = {
    "salvage": (0, 255, 100),    # Green
    "equipment": (255, 200, 0),  # Orange/Yellow
    "tactical": (255, 50, 50),   # Red
    "information": (0, 200, 255), # Blue/Cyan
}

for cat, color in categories.items():
    create_category_button(cat.capitalize(), f"mods/apis/sl_gui/textures/gui_category_{cat}.png", color=color)
