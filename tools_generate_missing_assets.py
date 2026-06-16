#!/usr/bin/env python3
"""Generate missing placeholder assets for SystemTest.

Creates lightweight procedural PNG textures/icons, OBJ placeholder meshes, valid B3D
stand-ins for accessory models, and OGG/Vorbis sounds.  The assets are designed
for Luanti/Minetest prototype use: small, deterministic, and easy to replace with
final art later.
"""
from __future__ import annotations

import math
import os
import shutil
from pathlib import Path
from typing import Iterable, Tuple

import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
SR = 22050
rng = np.random.default_rng(12345)


def ensure(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def font(size: int = 10):
    # Pillow's bundled default is fine and avoids external font dependencies.
    try:
        return ImageFont.truetype("DejaVuSans.ttf", size)
    except Exception:
        return ImageFont.load_default()


def save_png(img: Image.Image, path: Path) -> None:
    ensure(path.parent)
    img.save(path)


def add_label(draw: ImageDraw.ImageDraw, text: str, w: int, h: int, fill=(230, 245, 255, 230)):
    f = font(8 if len(text) > 10 else 10)
    words = text.replace("_", " ").split()
    lines = []
    line = ""
    for word in words:
        test = (line + " " + word).strip()
        if draw.textlength(test, font=f) <= w - 6:
            line = test
        else:
            if line:
                lines.append(line)
            line = word[:10]
    if line:
        lines.append(line)
    lines = lines[:3]
    total_h = len(lines) * 9
    y = max(2, (h - total_h) // 2)
    for line in lines:
        tw = draw.textlength(line, font=f)
        draw.text(((w - tw) / 2 + 1, y + 1), line, font=f, fill=(0, 0, 0, 180))
        draw.text(((w - tw) / 2, y), line, font=f, fill=fill)
        y += 9


def texture_base(name: str, color=(40, 45, 55), accent=(0, 220, 255), size=64, alpha=255) -> Image.Image:
    img = Image.new("RGBA", (size, size), (*color, alpha))
    px = img.load()
    for y in range(size):
        for x in range(size):
            n = int(rng.integers(0, 20))
            px[x, y] = (max(0, min(255, color[0] + n)), max(0, min(255, color[1] + n)), max(0, min(255, color[2] + n)), alpha)
    draw = ImageDraw.Draw(img, "RGBA")
    for x in range(0, size, 16):
        draw.line((x, 0, x, size), fill=(*accent, 95))
    for y in range(0, size, 16):
        draw.line((0, y, size, y), fill=(*accent, 70))
    draw.rectangle((0, 0, size - 1, size - 1), outline=(*accent, 210))
    return img


def make_neon_cube(path: Path):
    size = 64
    img = Image.new("RGBA", (size, size), (5, 7, 16, 255))
    draw = ImageDraw.Draw(img, "RGBA")
    for i in range(0, size, 8):
        a = 80 if i % 16 else 140
        draw.line((i, 0, i, size), fill=(0, 235, 255, a))
        draw.line((0, i, size, i), fill=(255, 0, 210, a))
    draw.rectangle((1, 1, size - 2, size - 2), outline=(0, 255, 255, 230), width=2)
    draw.rectangle((8, 8, size - 9, size - 9), outline=(255, 0, 200, 180), width=1)
    blurred = img.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.alpha_composite(blurred, img)
    save_png(img, path)


def make_icon(path: Path, name: str, color=(45, 60, 85), accent=(0, 220, 255), shape="box"):
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    draw.rounded_rectangle((3, 3, 60, 60), radius=8, fill=(*color, 245), outline=(*accent, 230), width=2)
    if shape == "hood":
        draw.pieslice((16, 10, 48, 46), 180, 360, fill=(55, 75, 100, 255), outline=(*accent, 220), width=2)
        draw.rectangle((18, 28, 46, 50), fill=(55, 75, 100, 255), outline=(*accent, 220), width=2)
    elif shape == "cap":
        draw.pieslice((16, 14, 46, 42), 180, 360, fill=(80, 55, 90, 255), outline=(*accent, 220), width=2)
        draw.polygon([(38, 28), (58, 32), (38, 36)], fill=(100, 70, 110, 255), outline=(*accent, 220))
    elif shape == "torso":
        draw.polygon([(20, 12), (44, 12), (52, 30), (45, 54), (19, 54), (12, 30)], fill=(50, 75, 105, 255), outline=(*accent, 220))
        draw.line((32, 14, 32, 52), fill=(*accent, 180), width=2)
    elif shape == "backpack":
        draw.rounded_rectangle((18, 10, 46, 55), radius=7, fill=(70, 80, 65, 255), outline=(*accent, 220), width=2)
        draw.rectangle((22, 18, 42, 32), outline=(230, 245, 255, 160), width=1)
    elif shape == "glove":
        draw.rounded_rectangle((20, 27, 48, 53), radius=7, fill=(75, 55, 45, 255), outline=(*accent, 220), width=2)
        for x in [22, 28, 34, 40]:
            draw.rounded_rectangle((x, 12, x + 7, 32), radius=3, fill=(75, 55, 45, 255), outline=(*accent, 150), width=1)
    elif shape == "leg":
        draw.rectangle((18, 10, 30, 54), fill=(45, 65, 85, 255), outline=(*accent, 220), width=2)
        draw.rectangle((34, 10, 46, 54), fill=(45, 65, 85, 255), outline=(*accent, 220), width=2)
    elif shape == "boot":
        draw.rectangle((23, 14, 38, 45), fill=(45, 40, 35, 255), outline=(*accent, 220), width=2)
        draw.rectangle((18, 41, 51, 54), fill=(45, 40, 35, 255), outline=(*accent, 220), width=2)
    else:
        draw.rectangle((18, 18, 46, 46), fill=(*accent, 120), outline=(230, 245, 255, 230), width=2)
    add_label(draw, name, size, size, fill=(245, 255, 255, 215))
    save_png(img, path)


def make_node_texture(path: Path, name: str, palette: str):
    palettes = {
        "wood": ((84, 55, 33), (220, 160, 80)),
        "metal": ((46, 50, 55), (150, 180, 210)),
        "tech": ((20, 32, 45), (0, 220, 255)),
        "hazard": ((30, 30, 25), (255, 215, 0)),
        "glass": ((30, 55, 65), (150, 235, 255)),
        "dark": ((18, 18, 25), (110, 120, 150)),
    }
    color, accent = palettes.get(palette, palettes["tech"])
    img = texture_base(name, color, accent)
    draw = ImageDraw.Draw(img, "RGBA")
    if "front" in name or "panel" in name or "rack" in name:
        for i in range(3):
            draw.rectangle((8, 10 + i * 15, 56, 18 + i * 15), outline=(*accent, 180), fill=(0, 0, 0, 55))
    if "caution" in name:
        for x in range(-64, 64, 16):
            draw.polygon([(x, 0), (x + 9, 0), (x + 73, 64), (x + 64, 64)], fill=(255, 205, 0, 190))
        draw.rectangle((0, 0, 63, 63), outline=(10, 10, 10, 255), width=3)
    if "hazard" in name:
        draw.polygon([(32, 8), (57, 54), (7, 54)], outline=(255, 215, 0, 255), width=3)
        draw.text((29, 26), "!", font=font(20), fill=(255, 215, 0, 255))
    if "radiation" in name:
        draw.ellipse((14, 14, 50, 50), outline=(255, 215, 0, 255), width=3)
        draw.ellipse((27, 27, 37, 37), fill=(255, 215, 0, 255))
        for ang in [90, 210, 330]:
            a = math.radians(ang)
            pts = [(32, 32), (32 + 22 * math.cos(a - .35), 32 - 22 * math.sin(a - .35)), (32 + 22 * math.cos(a + .35), 32 - 22 * math.sin(a + .35))]
            draw.polygon(pts, fill=(255, 215, 0, 190))
    if "biohazard" in name:
        for cx, cy in [(32, 20), (22, 39), (42, 39)]:
            draw.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), outline=(180, 255, 90, 255), width=3)
        draw.ellipse((27, 29, 37, 39), fill=(180, 255, 90, 255))
    if "window" in name:
        draw.rectangle((10, 10, 54, 54), fill=(120, 220, 255, 80), outline=(190, 245, 255, 230), width=3)
        if "broken" in name:
            draw.line((12, 14, 40, 36, 30, 54), fill=(230, 255, 255, 250), width=2)
            draw.line((52, 20, 35, 37), fill=(230, 255, 255, 250), width=2)
    add_label(draw, name, 64, 64)
    save_png(img, path)


def make_cursor(path: Path):
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    c = (0, 255, 255, 230)
    d.ellipse((13, 13, 18, 18), outline=c, width=1)
    d.line((16, 2, 16, 10), fill=c, width=1)
    d.line((16, 22, 16, 30), fill=c, width=1)
    d.line((2, 16, 10, 16), fill=c, width=1)
    d.line((22, 16, 30, 16), fill=c, width=1)
    save_png(img, path)


def make_hud(path: Path, frame_only=False):
    img = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle((4, 4, 252, 60), radius=8, fill=(5, 10, 20, 130 if not frame_only else 40), outline=(0, 220, 255, 220), width=2)
    for i, label in enumerate(["O2", "HP", "SIG"]):
        y = 10 + i * 16
        d.text((12, y - 2), label, font=font(10), fill=(210, 245, 255, 230))
        d.rectangle((42, y, 236, y + 8), outline=(0, 220, 255, 180), width=1)
        if not frame_only:
            fill = [(0, 220, 255, 160), (255, 70, 100, 160), (255, 215, 0, 140)][i]
            d.rectangle((44, y + 2, 150 + i * 25, y + 6), fill=fill)
    save_png(img, path)


def make_font_sheet(path: Path):
    img = Image.new("RGBA", (128, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    chars = "0123456789:-%"
    f = font(16)
    for i, ch in enumerate(chars):
        x = (i % 8) * 16
        y = (i // 8) * 24
        d.rectangle((x, y, x + 15, y + 23), outline=(0, 180, 255, 60))
        d.text((x + 3, y + 3), ch, font=f, fill=(0, 245, 255, 245))
    save_png(img, path)


def make_noise_textures(base: Path):
    ensure(base)
    for rainbow in [False, True]:
        for anim in [False, True]:
            frames = 4 if anim else 1
            img = Image.new("RGBA", (64, 64 * frames), (0, 0, 0, 255))
            px = img.load()
            for y in range(64 * frames):
                for x in range(64):
                    v = int(rng.integers(0, 256))
                    if rainbow:
                        # HSV-ish procedural rainbow noise.
                        r = int((math.sin((x + v) * .12) * .5 + .5) * 255)
                        g = int((math.sin((y + v) * .10 + 2) * .5 + .5) * 255)
                        b = int((math.sin((x + y + v) * .08 + 4) * .5 + .5) * 255)
                    else:
                        r = g = b = v
                    px[x, y] = (r, g, b, 255)
            name = f"sus_nodes_{'rainbow' if rainbow else 'white'}_noise_{'anim' if anim else 'noanim'}_4n.png"
            save_png(img, base / name)


# ---------- OBJ generation ----------
class OBJ:
    def __init__(self):
        self.v = []
        self.vt = []
        self.f = []

    def add_box(self, center, size, name="box"):
        cx, cy, cz = center
        sx, sy, sz = (s / 2 for s in size)
        verts = [
            (cx - sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz - sz), (cx + sx, cy + sy, cz - sz), (cx - sx, cy + sy, cz - sz),
            (cx - sx, cy - sy, cz + sz), (cx + sx, cy - sy, cz + sz), (cx + sx, cy + sy, cz + sz), (cx - sx, cy + sy, cz + sz),
        ]
        faces = [(1, 2, 3, 4), (5, 8, 7, 6), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 8, 4), (5, 1, 4, 8)]
        base_v = len(self.v)
        base_t = len(self.vt)
        self.v.extend(verts)
        self.vt.extend([(0, 0), (1, 0), (1, 1), (0, 1)] * 6)
        for i, face in enumerate(faces):
            self.f.append((name, [(base_v + idx, base_t + i * 4 + j + 1) for j, idx in enumerate(face)]))

    def add_octahedron(self, center, radius, name="octa"):
        cx, cy, cz = center
        verts = [(cx, cy + radius, cz), (cx + radius, cy, cz), (cx, cy, cz + radius), (cx - radius, cy, cz), (cx, cy, cz - radius), (cx, cy - radius, cz)]
        faces = [(1, 2, 3), (1, 3, 4), (1, 4, 5), (1, 5, 2), (6, 3, 2), (6, 4, 3), (6, 5, 4), (6, 2, 5)]
        base_v = len(self.v)
        base_t = len(self.vt)
        self.v.extend(verts)
        self.vt.extend([(0.5, 1), (1, 0), (0, 0)] * len(faces))
        for i, face in enumerate(faces):
            self.f.append((name, [(base_v + idx, base_t + i * 3 + j + 1) for j, idx in enumerate(face)]))

    def add_ring(self, inner=0.75, outer=1.0, y=0, segments=40, name="ring"):
        base_v = len(self.v)
        base_t = len(self.vt)
        for i in range(segments):
            a = 2 * math.pi * i / segments
            self.v.append((math.cos(a) * outer, y, math.sin(a) * outer))
            self.v.append((math.cos(a) * inner, y, math.sin(a) * inner))
            self.vt.append((i / segments, 1))
            self.vt.append((i / segments, 0))
        for i in range(segments):
            j = (i + 1) % segments
            self.f.append((name, [
                (base_v + i * 2 + 1, base_t + i * 2 + 1),
                (base_v + j * 2 + 1, base_t + j * 2 + 1),
                (base_v + j * 2 + 2, base_t + j * 2 + 2),
                (base_v + i * 2 + 2, base_t + i * 2 + 2),
            ]))

    def write(self, path: Path, mtllib: str | None = None):
        ensure(path.parent)
        with open(path, "w", encoding="utf-8") as fp:
            fp.write("# Procedural placeholder OBJ generated for SystemTest\n")
            if mtllib:
                fp.write(f"mtllib {mtllib}\n")
            for v in self.v:
                fp.write("v %.4f %.4f %.4f\n" % v)
            for vt in self.vt:
                fp.write("vt %.4f %.4f\n" % vt)
            current = None
            for name, face in self.f:
                if name != current:
                    fp.write(f"g {name}\n")
                    current = name
                fp.write("f " + " ".join(f"{vi}/{ti}" for vi, ti in face) + "\n")


def write_mtl(path: Path, texture_name: str, color=(0.6, 0.8, 1.0)):
    ensure(path.parent)
    with open(path, "w", encoding="utf-8") as fp:
        fp.write("newmtl generated_material\n")
        fp.write("Kd %.3f %.3f %.3f\n" % color)
        fp.write("Ka 0.05 0.05 0.08\n")
        fp.write("Ks 0.2 0.2 0.25\n")
        fp.write(f"map_Kd ../textures/{texture_name}\n")


def make_model_textures(texdir: Path):
    specs = {
        "player_texture.png": (35, 55, 85, 0, 220, 255, "AGENT"),
        "monster_texture.png": (35, 20, 30, 255, 60, 120, "THREAT"),
        "platform_texture.png": (45, 48, 55, 255, 210, 70, "PLAT"),
        "terminal_texture.png": (20, 35, 45, 0, 255, 170, "TERM"),
        "door_texture.png": (50, 55, 65, 255, 210, 70, "DOOR"),
        "item_texture.png": (20, 50, 55, 0, 255, 255, "ITEM"),
        "pulse_texture.png": (5, 20, 30, 0, 230, 255, "PULSE"),
        "particle_texture.png": (40, 20, 20, 255, 80, 80, "FX"),
        "flare_light_texture.png": (45, 35, 10, 255, 230, 70, "FLARE"),
    }
    for fn, (r, g, b, ar, ag, ab, label) in specs.items():
        img = texture_base(label, (r, g, b), (ar, ag, ab))
        d = ImageDraw.Draw(img, "RGBA")
        add_label(d, label, 64, 64)
        save_png(img, texdir / fn)


def make_mvp_models(modeldir: Path, texdir: Path):
    ensure(modeldir); ensure(texdir)
    make_model_textures(texdir)
    # Player: blocky agent
    obj = OBJ()
    obj.add_box((0, 0.2, 0), (0.45, 0.85, 0.25), "torso")
    obj.add_box((0, 0.85, 0), (0.32, 0.32, 0.32), "head")
    obj.add_box((-0.34, 0.2, 0), (0.16, 0.75, 0.16), "arm_l")
    obj.add_box((0.34, 0.2, 0), (0.16, 0.75, 0.16), "arm_r")
    obj.add_box((-0.13, -0.55, 0), (0.18, 0.75, 0.18), "leg_l")
    obj.add_box((0.13, -0.55, 0), (0.18, 0.75, 0.18), "leg_r")
    obj.write(modeldir / "player.obj", "player.mtl")
    write_mtl(modeldir / "player.mtl", "player_texture.png")

    # Monster: elongated body + claws/spikes
    obj = OBJ()
    obj.add_box((0, 0.25, 0), (0.55, 1.15, 0.38), "body")
    obj.add_box((0, 1.0, 0), (0.42, 0.36, 0.42), "head")
    obj.add_box((-0.45, 0.1, 0.05), (0.15, 1.05, 0.15), "arm_l")
    obj.add_box((0.45, 0.1, 0.05), (0.15, 1.05, 0.15), "arm_r")
    for x in [-0.18, 0, 0.18]:
        obj.add_octahedron((x, 1.25, -0.02), 0.12, "spike")
    obj.add_box((-0.18, -0.65, 0), (0.16, 0.7, 0.16), "leg_l")
    obj.add_box((0.18, -0.65, 0), (0.16, 0.7, 0.16), "leg_r")
    obj.write(modeldir / "monster.obj", "monster.mtl")
    write_mtl(modeldir / "monster.mtl", "monster_texture.png", (0.8, 0.2, 0.3))

    # Platform
    obj = OBJ(); obj.add_box((0, 0, 0), (2.0, 0.18, 2.0), "deck")
    for x in [-0.82, 0.82]:
        for z in [-0.82, 0.82]: obj.add_box((x, -0.35, z), (0.15, 0.7, 0.15), "strut")
    obj.write(modeldir / "platform.obj", "platform.mtl"); write_mtl(modeldir / "platform.mtl", "platform_texture.png")

    # Terminal
    obj = OBJ(); obj.add_box((0, -0.15, 0), (0.65, 0.75, 0.45), "base"); obj.add_box((0, 0.35, -0.08), (0.78, 0.45, 0.18), "screen")
    obj.write(modeldir / "terminal.obj", "terminal.mtl"); write_mtl(modeldir / "terminal.mtl", "terminal_texture.png")

    # Door and hatch
    obj = OBJ(); obj.add_box((0, 0.35, 0), (1.0, 1.8, 0.16), "door"); obj.add_box((0.32, 0.35, -0.1), (0.08, 0.08, 0.08), "handle")
    obj.write(modeldir / "door.obj", "door.mtl"); write_mtl(modeldir / "door.mtl", "door_texture.png")
    obj = OBJ(); obj.add_box((0, 0, 0), (1.2, 0.12, 1.2), "hatch"); obj.add_box((0, 0.08, -0.28), (0.5, 0.08, 0.08), "handle")
    obj.write(modeldir / "hatch.obj", "door.mtl")

    # Pickups
    obj = OBJ(); obj.add_octahedron((0, 0, 0), 0.35, "item")
    obj.write(modeldir / "item.obj", "item.mtl"); obj.write(modeldir / "item_pickup.obj", "item.mtl"); write_mtl(modeldir / "item.mtl", "item_texture.png")

    # VFX
    obj = OBJ(); obj.add_ring(0.82, 1.0, 0, 64, "pulse")
    obj.write(modeldir / "pulse.obj", "pulse.mtl"); obj.write(modeldir / "scanner_pulse.obj", "pulse.mtl"); write_mtl(modeldir / "pulse.mtl", "pulse_texture.png")
    obj = OBJ(); obj.add_octahedron((0, 0, 0), 0.28, "flare")
    obj.write(modeldir / "flare_light.obj", "flare_light.mtl"); write_mtl(modeldir / "flare_light.mtl", "flare_light_texture.png")
    obj = OBJ()
    for i in range(12):
        a = i * math.pi * 2 / 12
        x, z = math.cos(a) * 0.42, math.sin(a) * 0.42
        obj.add_box((x / 2, 0, z / 2), (abs(x) + 0.04, 0.04, abs(z) + 0.04), "shard")
    obj.write(modeldir / "particle.obj", "particle.mtl"); obj.write(modeldir / "death_particle.obj", "particle.mtl"); write_mtl(modeldir / "particle.mtl", "particle_texture.png")


# ---------- Sound generation ----------
def env(n, attack=0.02, release=0.1):
    a = max(1, int(n * attack))
    r = max(1, int(n * release))
    e = np.ones(n, dtype=np.float32)
    e[:a] = np.linspace(0, 1, a)
    e[-r:] = np.linspace(1, 0, r)
    return e


def sine(freq, dur, amp=0.2):
    t = np.arange(int(SR * dur)) / SR
    return (amp * np.sin(2 * np.pi * freq * t)).astype(np.float32)


def noise(dur, amp=0.2):
    return (rng.uniform(-amp, amp, int(SR * dur))).astype(np.float32)


def write_ogg(path: Path, data: np.ndarray):
    ensure(path.parent)
    data = np.asarray(data, dtype=np.float32)
    if data.ndim == 1:
        mx = float(np.max(np.abs(data))) if len(data) else 0.0
        if mx > 0.98:
            data = data / mx * 0.98
    sf.write(path, data, SR, format="OGG", subtype="VORBIS")


def lowpass(x, k=9):
    kernel = np.ones(k, dtype=np.float32) / k
    return np.convolve(x, kernel, mode="same").astype(np.float32)


def make_sound(kind: str) -> np.ndarray:
    if kind == "ambience":
        dur = 10.0; t = np.arange(int(SR * dur)) / SR
        y = 0.10*np.sin(2*np.pi*48*t) + 0.05*np.sin(2*np.pi*91*t) + lowpass(noise(dur, 0.08), 200)
        for at in [2.2, 5.6, 8.1]:
            i = int(at*SR); blip = sine(760, .08, .08)*env(int(.08*SR), .05, .8)
            y[i:i+len(blip)] += blip[:max(0, min(len(blip), len(y)-i))]
        return (y*0.65).astype(np.float32)
    if kind == "music":
        dur = 12.0; t = np.arange(int(SR*dur))/SR
        pulse = (np.sin(2*np.pi*0.5*t)*0.5+0.5)**3
        return (0.10*np.sin(2*np.pi*55*t) + 0.05*np.sin(2*np.pi*82.5*t) + 0.05*np.sin(2*np.pi*110*t)*pulse).astype(np.float32)
    if kind in ("footstep_metal", "place"):
        y = noise(.42, .12); y += sine(190, .42, .22) + sine(620, .42, .08); return y*env(len(y), .01, .75)
    if kind == "footstep_water":
        y = lowpass(noise(.55, .28), 8); y += sine(120, .55, .05); return y*env(len(y), .02, .8)
    if kind == "hit":
        y = sine(95, .35, .35) + lowpass(noise(.35, .2), 4); return y*env(len(y), .005, .8)
    if kind == "damage":
        y = sine(160, .55, .25) + sine(78, .55, .18) + noise(.55, .05); return y*env(len(y), .005, .9)
    if kind == "click":
        y = sine(1600, .08, .28) + noise(.08, .04); return y*env(len(y), .005, .7)
    if kind == "alert":
        y = np.concatenate([sine(880, .18, .25), np.zeros(int(.06*SR)), sine(880, .18, .25), np.zeros(int(.06*SR)), sine(660, .25, .25)])
        return y*env(len(y), .005, .5)
    if kind == "swim":
        y = lowpass(noise(.8, .25), 16); return y*env(len(y), .02, .8)
    if kind in ("monster_idle", "mob_idle"):
        dur = 2.0; t=np.arange(int(SR*dur))/SR
        y = 0.22*np.sin(2*np.pi*(45+8*np.sin(2*np.pi*0.7*t))*t) + lowpass(noise(dur,.08), 50)
        return (y*env(len(y), .05, .4)).astype(np.float32)
    if kind in ("monster_chase", "scary_attack"):
        dur = 1.4; t=np.arange(int(SR*dur))/SR
        y = 0.28*np.sin(2*np.pi*(65+35*t)*t) + lowpass(noise(dur, .22), 8)
        return (y*env(len(y), .01, .7)).astype(np.float32)
    if kind == "mob_death":
        dur=1.8; t=np.arange(int(SR*dur))/SR
        y=0.35*np.sin(2*np.pi*(160-80*t/dur)*t)+lowpass(noise(dur,.2),12)
        return (y*env(len(y), .01, .9)).astype(np.float32)
    if kind == "radio_static":
        dur=2.5; y=noise(dur,.22); y=lowpass(y,3)
        # Gate for broken radio bursts.
        t=np.arange(len(y))/SR; gate=(np.sin(2*np.pi*7*t)>-0.2).astype(np.float32)
        return (y*gate*env(len(y), .01, .2)).astype(np.float32)
    if kind in ("level_up", "achievement_unlock"):
        notes = [523.25, 659.25, 783.99] if kind == "level_up" else [392, 523.25, 659.25, 1046.5]
        parts=[]
        for f0 in notes:
            y=sine(f0,.18,.22)+sine(f0*2,.18,.08); parts.append(y*env(len(y),.01,.5))
        return np.concatenate(parts).astype(np.float32)
    return sine(440, .2, .2)*env(int(SR*.2), .01, .5)


def create_all():
    # MVP mod container so non-code assets are shipped with the game.
    mvp = ROOT / "mods/content/sl_mvp_assets"
    ensure(mvp / "textures"); ensure(mvp / "models"); ensure(mvp / "sounds")
    (mvp / "mod.conf").write_text("name = sl_mvp_assets\ndescription = Generated placeholder MVP media: models, textures, UI, and sounds.\ndepends =\n", encoding="utf-8")
    make_neon_cube(mvp / "textures/neon_cube.png")
    make_cursor(mvp / "textures/cursor.png")
    make_hud(mvp / "textures/hud.png", frame_only=False)
    make_hud(mvp / "textures/hud_frame.png", frame_only=True)
    make_font_sheet(mvp / "textures/font.png")
    make_mvp_models(mvp / "models", mvp / "textures")

    for name in ["ambience", "music", "footstep_metal", "footstep_water", "hit", "damage", "place", "click", "alert", "swim", "monster_idle", "monster_chase", "radio_static"]:
        write_ogg(mvp / f"sounds/{name}.ogg", make_sound(name))

    # Active/reference-specific missing assets.
    clothing_tex = ROOT / "mods/content/sl_clothing/textures"
    clothing_models = ROOT / "mods/content/sl_clothing/models"
    ensure(clothing_tex); ensure(clothing_models)
    icon_specs = {
        "character_tool_head_01.png": ("hood", "hood"), "character_tool_head_02.png": ("cap", "cap"),
        "character_tool_body_01.png": ("jacket", "torso"), "character_tool_body_02.png": ("coat", "torso"),
        "character_tool_back_01.png": ("pack", "backpack"),
        "character_tool_hand_01.png": ("glove L", "glove"), "character_tool_hand_02.png": ("glove R", "glove"),
        "character_tool_legs_01.png": ("pants L", "leg"), "character_tool_legs_02.png": ("pants R", "leg"),
        "character_tool_feet_01.png": ("boot L", "boot"), "character_tool_feet_02.png": ("boot R", "boot"),
    }
    for fn, (label, shape) in icon_specs.items():
        make_icon(clothing_tex / fn, label, shape=shape)
    # Valid B3D placeholders: copy existing tiny B3D stand-in so media loads cleanly.
    source_b3d = ROOT / "mods/content/sl_scary/models/scary_mob.b3d"
    for fn in ["hood.b3d", "cap.b3d", "jacket.b3d", "coat.b3d", "backpack.b3d", "glove_l.b3d", "glove_r.b3d", "trousers_l.b3d", "trousers_r.b3d", "boot_l.b3d", "boot_r.b3d", "clothing_hood.b3d"]:
        shutil.copyfile(source_b3d, clothing_models / fn)

    # Workshop texture TODOs (currently referenced in commented prototype code, but now present).
    workshop_tex = ROOT / "mods/content/workshops/textures"
    ensure(workshop_tex)
    workshop_specs = {
        "advanced_workbench_top.png":"wood", "advanced_workbench_bottom.png":"wood", "advanced_workbench_side.png":"wood", "advanced_workbench_front.png":"wood",
        "precision_anvil_top.png":"metal", "precision_anvil_bottom.png":"metal", "precision_anvil_side.png":"metal",
        "assembly_table_top.png":"tech", "assembly_table_bottom.png":"metal", "assembly_table_side.png":"metal",
        "tool_rack_top.png":"wood", "tool_rack_side.png":"wood",
        "chemical_station_top.png":"tech", "chemical_station_bottom.png":"metal", "chemical_station_side.png":"glass",
        "blueprint_drawer_top.png":"wood", "blueprint_drawer_side.png":"wood", "blueprint_drawer_front.png":"wood",
        "metal_locker_top.png":"metal", "metal_locker_side.png":"metal", "metal_locker_front.png":"metal",
        "filing_cabinet_top.png":"metal", "filing_cabinet_side.png":"metal", "filing_cabinet_front.png":"metal",
        "metal_desk_top.png":"metal", "metal_desk_bottom.png":"metal", "metal_desk_side.png":"metal", "metal_desk_front.png":"metal", "metal_desk_back.png":"metal",
        "lab_shelf_top.png":"metal", "lab_shelf_bottom.png":"metal", "lab_shelf_side.png":"metal",
        "server_rack_top.png":"tech", "server_rack_side.png":"tech", "server_rack_front.png":"tech", "server_rack_back.png":"tech",
        "control_panel_side.png":"tech", "control_panel_front.png":"tech", "control_panel_back.png":"tech",
        "vent_grate.png":"metal", "pipe_end.png":"metal", "pipe_side.png":"metal",
        "caution_tape.png":"hazard", "warning_sign_back.png":"metal", "warning_sign_hazard.png":"hazard", "warning_sign_radiation.png":"hazard", "warning_sign_biohazard.png":"hazard",
        "window_frame.png":"glass", "window_glass.png":"glass", "window_broken.png":"glass",
    }
    for fn, pal in workshop_specs.items():
        make_node_texture(workshop_tex / fn, fn.rsplit(".", 1)[0], pal)

    # sl_scary optional hide spot textures + missing sound IDs.
    scary_tex = ROOT / "mods/content/sl_scary/textures"
    ensure(scary_tex)
    for fn in ["hide_spot_top.png", "hide_spot_bottom.png", "hide_spot_side.png"]:
        make_node_texture(scary_tex / fn, fn.rsplit(".", 1)[0], "dark")
    scary_sounds = ROOT / "mods/content/sl_scary/sounds"
    for name in ["scary_attack", "mob_idle", "mob_death"]:
        write_ogg(scary_sounds / f"{name}.ogg", make_sound(name))

    # GUI missing sound IDs.
    gui_sounds = ROOT / "mods/apis/sl_gui/sounds"
    for name in ["achievement_unlock", "level_up"]:
        write_ogg(gui_sounds / f"{name}.ogg", make_sound(name))

    # sl_blocks ground animated/noanim noise textures.
    make_noise_textures(ROOT / "mods/sl_blocks/ground/textures")

    # Manifest for humans.
    manifest = ROOT / "GENERATED_ASSETS.md"
    manifest.write_text("""# Generated Missing Assets\n\nThis asset pass was generated procedurally for prototype use.  It fills missing media references found in the repository and the MVP list in `NEEDED ASSETS.md`.\n\n## Added\n\n- `mods/content/sl_mvp_assets/` — MVP placeholder models (`player.obj`, `monster.obj`, `platform.obj`, `terminal.obj`, `door.obj`, `hatch.obj`, `item.obj`, `item_pickup.obj`, `pulse.obj`, `scanner_pulse.obj`, `flare_light.obj`, `particle.obj`, `death_particle.obj`), textures/UI (`neon_cube.png`, `cursor.png`, `hud.png`, `hud_frame.png`, `font.png`, model textures), and OGG sounds (`ambience`, `music`, footsteps, alerts, monster cues, radio static, etc.).\n- `mods/content/sl_clothing/textures/` — inventory icons for all clothing items.\n- `mods/content/sl_clothing/models/` — valid B3D stand-ins for clothing/accessory model names.\n- `mods/content/workshops/textures/` — workshop/furniture/lab/sign/window node textures listed in the workshop prototype.\n- `mods/content/sl_scary/textures/` and `mods/content/sl_scary/sounds/` — hide spot textures plus `scary_attack.ogg`, `mob_idle.ogg`, and `mob_death.ogg`.\n- `mods/apis/sl_gui/sounds/` — `achievement_unlock.ogg` and `level_up.ogg`.\n- `mods/sl_blocks/ground/textures/` — white/rainbow noise animated and still textures.\n\n## Notes\n\nThese are intentionally lightweight placeholders: suitable for loading the game and testing gameplay loops, not final production art. Replace files in place as final assets become available.\n""", encoding="utf-8")


if __name__ == "__main__":
    create_all()
    print("Generated missing placeholder assets.")
