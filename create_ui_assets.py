from PIL import Image, ImageDraw

def create_category_button(text, filename, size=(256, 64)):
    # Dark grey background
    img = Image.new('RGBA', size, (26, 26, 26, 255))
    draw = ImageDraw.Draw(img)
    
    # Border
    border_color = (60, 60, 60, 255)
    draw.rectangle([0, 0, size[0]-1, size[1]-1], outline=border_color, width=2)
    
    # Neon Accent at the bottom
    accent_color = (0, 255, 255, 255) # Cyan for information
    draw.rectangle([2, size[1]-4, size[0]-3, size[1]-2], fill=accent_color)
    
    # Subtle inner glow
    for i in range(1, 4):
        alpha = 100 // i
        draw.rectangle([i, i, size[0]-1-i, size[1]-1-i], outline=(0, 255, 255, alpha))

    img.save(filename)

create_category_button("Information", "mods/apis/sl_gui/textures/gui_category_information.png")
