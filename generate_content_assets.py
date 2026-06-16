#!/usr/bin/env python3
"""Generate placeholder textures for the System Looting content pass.

Creates simple labelled icons for the new sl_modebase craftitems, tools,
interactive nodes and crafting categories.  These are intentionally
prototype-quality and can be replaced by final art later.
"""
from __future__ import annotations

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent


def ensure(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def font(size: int = 10) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype("DejaVuSans.ttf", size)
    except Exception:
        return ImageFont.load_default()


def make_icon(path: Path, label: str, color: tuple[int, int, int]) -> None:
    size = 64
    img = Image.new("RGBA", (size, size), (20, 22, 26, 255))
    draw = ImageDraw.Draw(img, "RGBA")
    draw.rectangle((2, 2, size - 3, size - 3), outline=(*color, 230), width=3)
    draw.rectangle((8, 8, size - 9, size - 9), fill=(*color, 55))

    f = font(10 if len(label) <= 6 else 8)
    # Simple word wrap for short labels
    words = label.split()
    lines = []
    line = ""
    for word in words:
        test = (line + " " + word).strip()
        if draw.textlength(test, font=f) <= size - 10:
            line = test
        else:
            if line:
                lines.append(line)
            line = word[:6]
    if line:
        lines.append(line)
    lines = lines[:3]

    total_h = len(lines) * 10
    y = max(2, (size - total_h) // 2)
    for ln in lines:
        bbox = draw.textbbox((0, 0), ln, font=f)
        w = bbox[2] - bbox[0]
        draw.text(((size - w) // 2, y), ln, font=f, fill=(240, 245, 255, 255))
        y += 10

    ensure(path.parent)
    img.save(path)


def make_node_texture(path: Path, label: str, color: tuple[int, int, int]) -> None:
    size = 64
    img = Image.new("RGBA", (size, size), (*color, 255))
    draw = ImageDraw.Draw(img, "RGBA")
    draw.rectangle((0, 0, size - 1, size - 1), outline=(255, 255, 255, 130), width=2)
    f = font(10)
    bbox = draw.textbbox((0, 0), label, font=f)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((size - w) // 2, (size - h) // 2), label, font=f, fill=(255, 255, 255, 255))
    ensure(path.parent)
    img.save(path)


# sl_modebase craftitems / tools / tactical items
modebase_tex = ROOT / "mods/game/sl_modebase/textures"
modebase_icons = {
    "sl_scrap_metal.png": ("Scrap", (150, 155, 160)),
    "sl_electronic_waste.png": ("E-Waste", (80, 165, 80)),
    "sl_raw_crystal.png": ("Crystal", (0, 210, 230)),
    "sl_plastic_scrap.png": ("Plastic", (200, 120, 200)),
    "sl_metal_ingot.png": ("Ingot", (185, 185, 195)),
    "sl_circuit_board.png": ("Circuit", (0, 190, 100)),
    "sl_energy_crystal.png": ("Energy", (0, 230, 255)),
    "sl_hardened_plate.png": ("Plate", (100, 105, 115)),
    "sl_reinforced_glass.png": ("Glass", (160, 200, 220)),
    "sl_combat_blade.png": ("Blade", (220, 220, 230)),
    "sl_breaching_pick.png": ("Pick", (180, 180, 190)),
    "sl_tactical_axe.png": ("Axe", (180, 140, 80)),
    "sl_trench_shovel.png": ("Shovel", (140, 120, 100)),
    "sl_energy_blade.png": ("E-Blade", (0, 220, 255)),
    "sl_power_drill.png": ("Drill", (200, 180, 60)),
    "sl_flare.png": ("Flare", (255, 140, 0)),
    "sl_medkit.png": ("Medkit", (220, 40, 40)),
    "sl_power_cell.png": ("Cell", (0, 220, 255)),
    "sl_blast_shield.png": ("Shield", (80, 120, 160)),
    "sl_barricade.png": ("Wall", (120, 120, 130)),
    "sl_signal_relay.png": ("Relay", (200, 160, 0)),
    "sl_sensor_array.png": ("Sensor", (0, 180, 220)),
    "sl_objective_core.png": ("Core", (0, 255, 100)),
    "sl_loot_crate.png": ("Loot", (80, 140, 80)),
}
for filename, (label, color) in modebase_icons.items():
    make_icon(modebase_tex / filename, label, color)

# Crafting category icons (overwriting the blank placeholders)
category_icons = {
    "gui_category_salvage.png": ("Salvage", (120, 120, 130)),
    "gui_category_equipment.png": ("Equip", (180, 180, 190)),
    "gui_category_tactical.png": ("Tactical", (200, 160, 0)),
    "gui_category_objective.png": ("Objective", (0, 255, 100)),
}
for filename, (label, color) in category_icons.items():
    make_icon(ROOT / "mods/apis/sl_gui/textures" / filename, label, color)

print("Generated System Looting content textures.")
