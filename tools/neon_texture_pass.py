#!/usr/bin/env python3
"""Neon-grid texture pass for mods/default/textures.

Replaces every texture of the `default` mod with neon-grid style artwork
matching the game's ground tiles (mods/sl_blocks/ground/textures/*_neon.png):
glowing wireframe / grid-line art on deep black, cyberpunk vector-neon style.

Pipeline (run steps in order):
  1. AI texture sheets (1024x1024) are generated into SHEETS_DIR (outside the
     repo) with `tools/neon_texture_pass.py prompts` output as a guide.
     Each sheet holds a 4x4 (or 3x3) grid of cells; every cell is a texture
     upscaled on a strict pixel-art lattice (16x16 texture -> 256x256 cell,
     i.e. 16x16 logical pixels of 16x16 real pixels each).
  2. `process` splits every sheet into cells, downscales each cell back by the
     same power (BOX area filter -> exact pixel-art downscale) and writes the
     final PNGs over the originals in mods/default/textures.
     Textures whose original used transparency become alpha-keyed cutouts:
     pure black -> fully transparent, glowing neon -> opaque.
  3. `assemble` builds the animated strips (water / lava / torch / furnace /
     crack_anylength) from the processed stills.

Only Pillow is required.
"""

import math
import os
import sys
import json

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXDIR = os.path.join(ROOT, "mods", "default", "textures")
SHEETS_DIR = os.environ.get("NEON_SHEETS_DIR", os.path.join(ROOT, "neon_sheets"))

# ---------------------------------------------------------------- manifest --

# kind: tile    = seamless edge-to-edge tile (opaque)
#        tilea   = edge-to-edge tile with alpha (small black gaps keyed out)
#        sprite  = centered cutout sprite on pure black (alpha keyed)
# Special targets (own sheets / procedural) are listed after the grid batches.

B = {}  # texfile -> dict(sheet, cell, kind, size, desc)

def sheet(name, cells, kind, size=(16, 16)):
    """cells: list of (texfile, description) in row-major order."""
    for i, (tex, desc) in enumerate(cells):
        assert tex not in B, tex
        B[tex] = dict(sheet=name, cell=i, kind=kind, size=size, desc=desc)

# ---- B01 stone & ground basics ----------------------------------------------
sheet("B01_stone_ground", [
    ("default_stone.png",             "[hue cyan #29E6FF] dark stone panel, thin cyan neon wire grid, corner ticks"),
    ("default_cobble.png",            "[hue cyan #29E6FF] cobblestone cells outlined by thin cyan neon seams on near-black, seamless tile"),
    ("default_mossycobble.png",       "[hue green #39FF6E] cobblestone cells with neon green glow in the joints, seamless tile"),
    ("default_stone_brick.png",       "[hue cyan #29E6FF] offset bricks, thin glowing cyan neon mortar lines, seamless tile"),
    ("default_stone_block.png",       "[hue cyan #29E6FF] smooth dark slab, hairline cyan neon border, faint inner cross seam"),
    ("default_gravel.png",            "[hue pale blue #9FD8FF] small pebbles outlined in pale blue neon on near-black, dense seamless tile"),
    ("default_sand.png",              "[hue amber #FFB347] dark sand tile with dotted amber neon ripples"),
    ("default_silver_sand.png",       "[hue ice blue #BFE8FF] speckle field of tiny ice-blue neon dots on blue-black"),
    ("default_clay.png",              "[hue violet #B78CFF] dark clay tile with sparse violet neon tracery"),
    ("default_dirt.png",              "[hue amber #FFB347] black-brown soil with a few tiny dim amber neon specks"),
    ("default_dry_dirt.png",          "[hue orange #FF7A2F] cracked dark earth, thin glowing orange neon crack lines"),
    ("default_permafrost.png",        "[hue ice blue #BFE8FF] blue-black frozen soil with tiny pale ice neon glints"),
    ("default_grass.png",             "[hue green #39FF6E] black turf tile with a crisp grid of neon green grass blade lines, seamless"),
    ("default_dry_grass.png",         "[hue amber #FFC44D] black turf tile with sparse amber neon grass lines"),
    ("default_snow.png",              "[hue ice blue #BFE8FF] near-black frost tile with delicate ice-blue neon glitter lattice"),
    ("default_ice.png",               "[hue ice blue #BFE8FF] deep black ice tile with glowing ice-blue neon fracture lines"),
], "tile")

# ---- B02 desert / sandstone / obsidian --------------------------------------
sheet("B02_desert_obsidian", [
    ("default_desert_sand.png",           "[hue orange #FF7A2F] dark rust sand tile with orange neon ripples"),
    ("default_desert_cobble.png",         "[hue orange #FF7A2F] cobble cells with orange neon seams"),
    ("default_desert_stone.png",          "[hue red #FF4D6B] dark maroon panel with faint red neon wire grid"),
    ("default_desert_stone_block.png",    "[hue red #FF4D6B] maroon slab with red neon hairline border"),
    ("default_desert_stone_brick.png",    "[hue red #FF4D6B] maroon bricks with red neon mortar"),
    ("default_sandstone.png",             "[hue amber #FFB347] dark amber slab with faint horizontal amber neon strata"),
    ("default_sandstone_block.png",       "[hue amber #FFB347] amber panel with amber neon border grid"),
    ("default_sandstone_brick.png",       "[hue amber #FFB347] amber bricks with amber neon mortar"),
    ("default_silver_sandstone.png",      "[hue ice blue #BFE8FF] cool blue slab with ice-blue neon border grid"),
    ("default_silver_sandstone_block.png","[hue ice blue #BFE8FF] blue-grey panel with pale blue neon frame"),
    ("default_silver_sandstone_brick.png","[hue ice blue #BFE8FF] blue-grey bricks with ice-blue neon mortar"),
    ("default_obsidian.png",              "[hue violet #A96CFF] near-black obsidian with violet neon wire grid"),
    ("default_obsidian_block.png",        "[hue violet #A96CFF] black slab with violet neon border"),
    ("default_obsidian_brick.png",        "[hue violet #A96CFF] dark violet bricks with violet neon mortar"),
    ("default_moss.png",                  "[hue green #39FF6E] neon green moss patch glow on near-black, seamless tile"),
    ("default_cloud.png",                 "[hue ice blue #BFE8FF] soft cloud puffs outlined in faint ice-blue neon grid on dark slate"),
], "tile")

# ---- B03 sides, litter, ground overlays --------------------------------------
sheet("B03_sides_overlays", [
    ("default_grass_side.png",              "[hue green #39FF6E] side tile: black soil with ONE neon green strip along the very top edge only"),
    ("default_dry_grass_side.png",          "[hue amber #FFC44D] side tile: black soil with one amber neon strip along the top edge"),
    ("default_snow_side.png",               "[hue ice blue #BFE8FF] side tile: black soil with one ice-blue neon strip along the top edge"),
    ("default_moss_side.png",               "[hue green #39FF6E] side tile: black stone with neon green drip veins from the top edge"),
    ("default_stones_side.png",             "[hue pale blue #9FD8FF] side tile: black soil with a few small pale-blue neon pebbles near the top edge"),
    ("default_stones.png",                  "[hue pale blue #9FD8FF] a few small pale-blue neon pebbles on pure black"),
    ("default_coniferous_litter.png",       "[hue teal #2FE8C8] black forest floor tile with tiny teal neon needles scattered"),
    ("default_coniferous_litter_side.png",  "[hue teal #2FE8C8] side tile: black soil with a thin teal neon needle fringe along the top edge"),
    ("default_rainforest_litter.png",       "[hue green #6EFF5E] black humus floor tile with tiny green neon specks"),
    ("default_rainforest_litter_side.png",  "[hue green #6EFF5E] side tile: black soil with a thin green neon fringe along the top edge"),
    ("default_footprint.png",               "[hue cyan #29E6FF] one cyan neon boot footprint outline on pure black"),
    ("default_invisible_node_overlay.png",  "[hue white #EAF6FF] four tiny faint white corner brackets near the edges on pure black"),
    ("default_papyrus.png",                 "[hue green #39FF6E] three tall thin neon green reeds on pure black"),
    ("default_kelp.png",                    "[hue green #4DFFB8] one tall wavy neon green seaweed strand on pure black"),
    ("default_glass_detail.png",            "[hue cyan #29E6FF] a few tiny cyan neon sparkle glints on pure black"),
    ("default_obsidian_glass_detail.png",   "[hue violet #A96CFF] a few tiny violet neon sparkle glints on pure black"),
], "sprite")
for t in ["default_grass_side.png", "default_dry_grass_side.png", "default_snow_side.png",
          "default_moss_side.png", "default_coniferous_litter.png", "default_rainforest_litter.png"]:
    B[t]["kind"] = "tile"
for t in ["default_stones_side.png", "default_coniferous_litter_side.png",
          "default_rainforest_litter_side.png"]:
    B[t]["kind"] = "tilea"

# ---- B04 trees & cactus -------------------------------------------------------
sheet("B04_trees", [
    ("default_tree.png",                  "oak bark tile: dark vertical bark ridges with thin amber glowing striations"),
    ("default_tree_top.png",              "tree trunk top: concentric glowing amber rings on dark wood"),
    ("default_jungletree.png",            "jungle bark tile: dark ridges with glowing magenta vine lines"),
    ("default_jungletree_top.png",        "concentric glowing magenta rings on dark wood"),
    ("default_pine_tree.png",             "pine bark tile: dark ridges with glowing teal streaks"),
    ("default_pine_tree_top.png",         "concentric glowing teal rings on dark wood"),
    ("default_acacia_tree.png",           "acacia bark tile: dark ridges with glowing red-orange chevrons"),
    ("default_acacia_tree_top.png",       "concentric glowing red-orange rings on dark wood"),
    ("default_aspen_tree.png",            "pale aspen bark tile with glowing cyan dash marks"),
    ("default_aspen_tree_top.png",        "concentric glowing pale cyan rings on dark wood"),
    ("default_cactus_side.png",           "cactus side tile: dark green columns with vertical neon green spine dot lines"),
    ("default_cactus_top.png",            "cactus top tile: dark green pad with a neon green spine star cluster in the center"),
    ("default_large_cactus_seedling.png", "tiny glowing green cactus seedling sprite on pure black"),
    ("default_bush_stem.png",             "short thin brown twig with faint amber glow, sprite on pure black"),
    ("default_acacia_bush_stem.png",      "short thin twig with red-orange glow, sprite on pure black"),
    ("default_pine_bush_stem.png",        "short thin twig with teal glow, sprite on pure black"),
], "sprite")  # first 12 are tiles really; kind overridden below
for t in ["default_tree.png", "default_tree_top.png", "default_jungletree.png",
          "default_jungletree_top.png", "default_pine_tree.png", "default_pine_tree_top.png",
          "default_acacia_tree.png", "default_acacia_tree_top.png", "default_aspen_tree.png",
          "default_aspen_tree_top.png", "default_cactus_side.png", "default_cactus_top.png"]:
    B[t]["kind"] = "tile"

# ---- B05 wood planks & fences --------------------------------------------------
sheet("B05_wood_fences", [
    ("default_wood.png",                 "[hue amber #FFB347] oak planks tile: near-black boards with thin amber neon seams, horizontal"),
    ("default_junglewood.png",           "[hue magenta #FF4DC4] jungle planks tile: near-black boards with magenta neon seams"),
    ("default_pine_wood.png",            "[hue teal #2FE8C8] pine planks tile: near-black boards with teal neon seams"),
    ("default_aspen_wood.png",           "[hue pale cyan #9FD8FF] aspen planks tile: near-black boards with pale cyan neon seams"),
    ("default_acacia_wood.png",          "[hue orange #FF7A2F] acacia planks tile: near-black boards with orange neon seams"),
    ("default_fence_wood.png",           "[hue amber #FFB347] one vertical fence post with two horizontal rails, thin amber neon outline, sprite on pure black"),
    ("default_fence_junglewood.png",     "[hue magenta #FF4DC4] vertical fence post with rails, magenta neon outline, sprite on pure black"),
    ("default_fence_pine_wood.png",      "[hue teal #2FE8C8] vertical fence post with rails, teal neon outline, sprite on pure black"),
    ("default_fence_aspen_wood.png",     "[hue pale cyan #9FD8FF] vertical fence post with rails, pale cyan neon outline, sprite on pure black"),
    ("default_fence_acacia_wood.png",    "[hue orange #FF7A2F] vertical fence post with rails, orange neon outline, sprite on pure black"),
    ("default_fence_rail_wood.png",      "[hue amber #FFB347] two thin horizontal rails with small posts, amber neon outline, sprite on pure black"),
    ("default_fence_rail_junglewood.png","[hue magenta #FF4DC4] two thin horizontal rails, magenta neon outline, sprite on pure black"),
    ("default_fence_rail_pine_wood.png", "[hue teal #2FE8C8] two thin horizontal rails, teal neon outline, sprite on pure black"),
    ("default_fence_rail_aspen_wood.png","[hue pale cyan #9FD8FF] two thin horizontal rails, pale cyan neon outline, sprite on pure black"),
    ("default_fence_rail_acacia_wood.png","[hue orange #FF7A2F] two thin horizontal rails, orange neon outline, sprite on pure black"),
    ("default_fence_overlay.png",        "[hue cyan #29E6FF] thin fence rails drawn as cyan neon outline overlay, sprite on pure black"),
], "sprite")
for t in ["default_wood.png", "default_junglewood.png", "default_pine_wood.png",
          "default_aspen_wood.png", "default_acacia_wood.png"]:
    B[t]["kind"] = "tile"

# ---- B06 leaves (alpha tiles) ---------------------------------------------------
sheet("B06_leaves", [
    ("default_leaves.png",                "[hue green #39FF6E] dense oak canopy: leaf clusters webbed by neon green vein lines, small pure-black gaps, fills the whole square"),
    ("default_leaves_simple.png",         "[hue green #39FF6E] sparse neon green leaf vein web, larger pure-black gaps, fills the square"),
    ("default_jungleleaves.png",          "[hue magenta #FF4DC4] dense jungle canopy webbed by magenta neon veins, small pure-black gaps"),
    ("default_jungleleaves_simple.png",   "[hue magenta #FF4DC4] sparse magenta neon canopy web, larger gaps"),
    ("default_pine_needles.png",          "[hue teal #2FE8C8] dense teal neon needle mesh, tiny pure-black gaps"),
    ("default_acacia_leaves.png",         "[hue orange #FF7A2F] fine orange neon foliage web, small pure-black gaps"),
    ("default_acacia_leaves_simple.png",  "[hue orange #FF7A2F] sparse orange neon foliage web, larger gaps"),
    ("default_aspen_leaves.png",          "[hue pale cyan #9FD8FF] pale cyan neon canopy web, small gaps"),
    ("default_blueberry_bush_leaves.png", "[hue green #39FF6E] green neon bush canopy web dotted with a few bright blue neon berries, small gaps"),
    ("default_sapling.png",               "[hue green #39FF6E] tiny oak sapling: thin dark trunk with a small neon green leaf tuft, sprite on pure black"),
    ("default_junglesapling.png",         "[hue magenta #FF4DC4] jungle sapling: thin trunk with magenta neon leaves, sprite on pure black"),
    ("default_pine_sapling.png",          "[hue teal #2FE8C8] small pine sapling: teal neon triangular needle tiers, sprite on pure black"),
    ("default_acacia_sapling.png",        "[hue orange #FF7A2F] small acacia sapling with orange neon canopy, sprite on pure black"),
    ("default_aspen_sapling.png",         "[hue pale cyan #9FD8FF] slender aspen sapling with pale cyan neon leaves, sprite on pure black"),
    ("default_emergent_jungle_sapling.png","[hue magenta #FF4DC4] tall jungle sapling with layered magenta neon canopy, sprite on pure black"),
    ("default_bush_sapling.png",          "[hue green #39FF6E] small bush sapling with green neon leaves, sprite on pure black"),
], "tilea")
for t in ["default_sapling.png", "default_junglesapling.png", "default_pine_sapling.png",
          "default_acacia_sapling.png", "default_aspen_sapling.png",
          "default_emergent_jungle_sapling.png", "default_bush_sapling.png"]:
    B[t]["kind"] = "sprite"

# ---- B07 grass, plants --------------------------------------------------------
sheet("B07_plants", [
    ("default_grass_1.png",        "short neon green grass tuft, few blades, sprite centered on pure black"),
    ("default_grass_2.png",        "neon green grass tuft, medium height, sprite on pure black"),
    ("default_grass_3.png",        "tall neon green grass tuft with bending blade tips, sprite on pure black"),
    ("default_grass_4.png",        "thick neon green grass clump, sprite on pure black"),
    ("default_grass_5.png",        "tall sparse neon green grass with seed dots on tips, sprite on pure black"),
    ("default_dry_grass_1.png",    "short amber-yellow dry grass tuft, sprite on pure black"),
    ("default_dry_grass_2.png",    "medium amber dry grass tuft, sprite on pure black"),
    ("default_dry_grass_3.png",    "tall amber dry grass with bent tips, sprite on pure black"),
    ("default_dry_grass_4.png",    "thick amber dry grass clump, sprite on pure black"),
    ("default_dry_grass_5.png",    "sparse tall dry grass with seed dots, sprite on pure black"),
    ("default_marram_grass_1.png", "short teal-green marram grass tuft, curled blades, sprite on pure black"),
    ("default_marram_grass_2.png", "medium teal-green marram grass, sprite on pure black"),
    ("default_marram_grass_3.png", "tall teal-green marram grass with curling tips, sprite on pure black"),
    ("default_fern_1.png",         "small fern with glowing green fronds, sprite on pure black"),
    ("default_dry_shrub.png",      "scraggly dead bush, thin amber-glowing bare twigs, sprite on pure black"),
    ("default_junglegrass.png",    "dense tall jungle grass clump with green and magenta blades, sprite on pure black"),
], "sprite")

# ---- B08 bush saplings, fruits, small items -----------------------------------
sheet("B08_items_plants", [
    ("default_acacia_bush_sapling.png",   "[hue orange #FF7A2F] small sapling with orange neon leaf puffs, sprite on pure black"),
    ("default_pine_bush_sapling.png",     "[hue teal #2FE8C8] small sapling with teal neon needle puffs, sprite on pure black"),
    ("default_blueberry_bush_sapling.png","[hue green #39FF6E] small bush sapling with green neon leaves and tiny blue glow dots, sprite on pure black"),
    ("default_apple.png",                 "[hue red #FF3355] one large round apple drawn as a thick neon red outline circle with dark fill, tiny stem and one small leaf tick, centered sprite on pure black"),
    ("default_blueberries.png",           "[hue blue #4D9FFF] cluster of three small blue neon circle berries, sprite on pure black"),
    ("default_snowball.png",              "[hue ice blue #BFE8FF] one snowball: ice-blue neon circle outline with dark fill, sprite on pure black"),
    ("default_stick.png",                 "[hue amber #FFB347] one diagonal thin amber neon stick, two pixels thick, sprite on pure black"),
    ("default_paper.png",                 "[hue pale cyan #9FD8FF] paper sheet: pale cyan neon rectangle outline, dark fill, sprite on pure black"),
    ("default_book.png",                  "[hue cyan #29E6FF] closed book: cyan neon outline with a brighter spine edge, sprite on pure black"),
    ("default_flint.png",                 "[hue pale blue #9FD8FF] sharp flint flake: pale blue neon edge outline, sprite on pure black"),
    ("default_clay_lump.png",             "[hue violet #B78CFF] small clay blob: violet neon outline, sprite on pure black"),
    ("default_clay_brick.png",            "[hue violet #B78CFF] brick shape: violet neon outline, sprite on pure black"),
    ("default_coal_lump.png",             "[hue white-hot #FFE8C8] black coal lump with white-hot neon facet lines, sprite on pure black"),
    ("default_iron_lump.png",             "[hue orange #FF7A2F] rough ore lump: orange neon outline, sprite on pure black"),
    ("default_copper_lump.png",           "[hue orange #FFA03F] round copper lump: orange neon outline, sprite on pure black"),
    ("default_tin_lump.png",              "[hue silver-blue #C8E0FF] round tin lump: silver-blue neon outline, sprite on pure black"),
], "sprite")

# ---- B09 liquids, glass, lights ------------------------------------------------
sheet("B09_liquid_glass", [
    ("default_water.png",                "full-square water surface tile: dark deep-blue liquid with glowing cyan wave lines, small pure-black gaps, fills the whole square"),
    ("default_river_water.png",          "full-square river water tile: dark teal liquid with glowing turquoise wave lines, small gaps"),
    ("default_lava.png",                 "full-square lava tile: near-black magma crust with glowing orange-red crack veins, fills the whole square"),
    ("default_glass.png",                "glass pane: thin glowing cyan frame at the edges with one diagonal highlight streak, large pure-black empty center"),
    ("default_obsidian_glass.png",       "glass pane with glowing violet frame and violet highlight streak, large pure-black center"),
    ("default_meselamp.png",             "bright lamp tile: intense yellow-white glowing core panel with thin brass grid lines"),
    ("default_mese_post_light_side.png", "side of a lamp post: vertical dark post with a bright yellow-white glowing band near the top, sprite edges at left and right, pure-black background"),
    ("default_mese_post_light_side_dark.png", "side of a lamp post: darker post with a dimmer glowing band, sprite on pure black"),
    ("default_torch_on_floor.png",       "hand torch: short dark stick with amber glow and a bright cyan-white flame on top, sprite on pure black"),
    ("default_furnace_fire_bg.png",      "dark fire pit: dim red-glowing coal bed outline, sprite on pure black"),
    ("default_furnace_fire_fg.png",      "bright orange-glowing flame tongues, sprite on pure black"),
    ("default_ladder_wood.png",          "wooden ladder: two vertical amber-glowing rails with rungs, sprite on pure black"),
    ("default_ladder_steel.png",         "steel ladder: two vertical cyan-glowing rails with thin rungs, sprite on pure black"),
    ("_var_water2.png",                  "second frame of flowing water: same dark blue liquid with glowing cyan wave lines shifted differently, fills the whole square"),
    ("_var_river2.png",                  "second frame of river water with shifted turquoise wave lines, fills the whole square"),
    ("_var_lava2.png",                   "second frame of lava crust with shifted orange crack veins, fills the whole square"),
], "sprite")
for t, k in [("default_water.png", "tilea"), ("default_river_water.png", "tilea"),
             ("default_lava.png", "tile"), ("default_meselamp.png", "tile"),
             ("_var_water2.png", "tilea"), ("_var_river2.png", "tilea"), ("_var_lava2.png", "tile")]:
    B[t]["kind"] = k

# ---- B10 ore minerals -----------------------------------------------------------
sheet("B10_minerals", [
    ("default_mineral_coal.png",    "sparse cluster of white-hot glowing coal specks on pure black, spread like ore inclusions, fills square like an overlay"),
    ("default_mineral_iron.png",    "sparse cluster of rust-orange glowing ore specks on pure black"),
    ("default_mineral_copper.png",  "sparse cluster of bright orange glowing copper specks on pure black"),
    ("default_mineral_tin.png",     "sparse cluster of silvery pale-blue glowing tin specks on pure black"),
    ("default_mineral_gold.png",    "sparse cluster of bright yellow glowing gold specks on pure black"),
    ("default_mineral_diamond.png", "sparse cluster of icy cyan-white sparkling diamond gems on pure black"),
    ("default_mineral_mese.png",    "sparse cluster of yellow-green glowing crystal shards on pure black"),
    ("default_gold_lump.png",       "one rounded gold lump glowing yellow, sprite on pure black"),
    ("default_diamond.png",         "one brilliant cyan-white glowing faceted diamond gem, sprite on pure black"),
    ("default_mese_crystal_fragment.png", "small yellow-green glowing crystal fragment, sprite on pure black"),
    ("default_mese_crystal.png",    "large upright yellow-green glowing crystal cluster, sprite on pure black"),
    ("default_obsidian_shard.png",  "sharp violet-glowing black obsidian shard, sprite on pure black"),
    ("default_steel_ingot.png",     "stacked metal ingot bars with pale blue-grey glow edges, sprite on pure black"),
    ("default_copper_ingot.png",    "stacked ingot bars glowing orange, sprite on pure black"),
    ("default_tin_ingot.png",       "stacked ingot bars glowing silvery white-blue, sprite on pure black"),
    ("default_bronze_ingot.png",    "stacked ingot bars glowing warm amber, sprite on pure black"),
], "sprite")

# ---- B11 metal blocks --------------------------------------------------------
sheet("B11_metal_blocks", [
    ("default_coal_block.png",    "compressed coal block tile: near-black with faint white-hot seams"),
    ("default_steel_block.png",   "riveted steel plate tile, pale blue-grey glow border with corner rivets"),
    ("default_copper_block.png",  "copper plate tile with orange glow border and rivets"),
    ("default_tin_block.png",     "tin plate tile with silvery glow border and rivets"),
    ("default_bronze_block.png",  "bronze plate tile with amber glow border and rivets"),
    ("default_gold_block.png",    "gold plate tile with bright yellow glow border and rivets"),
    ("default_diamond_block.png", "tile of cut cyan-white glowing diamond facets, jewel grid"),
    ("default_mese_block.png",    "tile of yellow-green glowing crystal facets"),
    ("default_brick.png",         "red brick wall tile with glowing red mortar lines, offset rows"),
    ("default_bookshelf.png",     "bookshelf tile: amber frame with two shelves of colorful glowing book spines (cyan, magenta, green)"),
    ("default_bookshelf_slot.png","single shelf slot with two glowing book spins, sprite on pure black"),
    ("default_chest_front.png",   "storage chest front: dark wood panel with amber-glowing frame, steel latch glowing cyan in the center"),
    ("default_chest_side.png",    "chest side: dark wood panel with amber-glowing frame"),
    ("default_chest_top.png",     "chest lid top: dark panel with amber glow border"),
    ("default_chest_lock.png",    "small cyan-glowing steel lock plate, sprite on pure black"),
    ("default_book_written.png",  "closed book with magenta-glowing cover edge and text lines, sprite on pure black"),
], "tile")
for t in ["default_bookshelf_slot.png", "default_chest_lock.png", "default_book_written.png"]:
    B[t]["kind"] = "sprite"

# ---- B12 furnace, signs, steel/bronze tools ------------------------------------
sheet("B12_furnace_signs", [
    ("default_furnace_front.png",  "[hue cyan #29E6FF] furnace front tile: near-black steel panel with thin cyan neon frame and a dark arched fire mouth in the lower center"),
    ("default_furnace_side.png",   "[hue cyan #29E6FF] furnace side tile: near-black steel panel with cyan neon hairline border"),
    ("default_furnace_top.png",    "[hue cyan #29E6FF] furnace top tile: near-black plate with cyan neon border and small vent dashes"),
    ("default_furnace_bottom.png", "[hue cyan #29E6FF] furnace bottom tile: near-black plate with faint cyan border"),
    ("default_sign_wood.png",      "[hue amber #FFB347] wooden sign: dark board with amber neon edge frame, sprite on pure black"),
    ("default_sign_wall_wood.png", "[hue amber #FFB347] wall sign board with amber neon frame, sprite on pure black"),
    ("default_sign_steel.png",     "[hue cyan #29E6FF] steel sign: near-black plate with cyan neon frame, sprite on pure black"),
    ("default_sign_wall_steel.png","[hue cyan #29E6FF] steel wall sign with cyan neon frame, sprite on pure black"),
    ("default_tool_steelaxe.png",  "[hue steel-blue #9FD8FF] axe icon: head drawn as a pale steel-blue neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_steelpick.png", "[hue steel-blue #9FD8FF] pickaxe icon: head as pale steel-blue neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_steelshovel.png","[hue steel-blue #9FD8FF] shovel icon: blade as pale steel-blue neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_steelsword.png","[hue steel-blue #9FD8FF] sword icon: blade as pale steel-blue neon outline, near-black guard and grip, diagonal, sprite on pure black"),
    ("default_tool_bronzeaxe.png", "[hue amber #FFB347] axe icon: head as amber neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_bronzepick.png","[hue amber #FFB347] pickaxe icon: head as amber neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_bronzeshovel.png","[hue amber #FFB347] shovel icon: blade as amber neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_bronzesword.png","[hue amber #FFB347] sword icon: blade as amber neon outline, near-black guard and grip, diagonal, sprite on pure black"),
], "tile")
for t in ["default_sign_wood.png", "default_sign_wall_wood.png", "default_sign_steel.png",
          "default_sign_wall_steel.png", "default_tool_steelaxe.png", "default_tool_steelpick.png",
          "default_tool_steelshovel.png", "default_tool_steelsword.png", "default_tool_bronzeaxe.png",
          "default_tool_bronzepick.png", "default_tool_bronzeshovel.png", "default_tool_bronzesword.png"]:
    B[t]["kind"] = "sprite"

# ---- B13 tools: mese / stone / diamond / wood ------------------------------------
sheet("B13_tools_1", [
    ("default_tool_meseaxe.png",      "[hue yellow-green #B8FF34] axe icon: head as yellow-green neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_mesepick.png",     "[hue yellow-green #B8FF34] pickaxe icon: head as yellow-green neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_meseshovel.png",   "[hue yellow-green #B8FF34] shovel icon: blade as yellow-green neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_mesesword.png",    "[hue yellow-green #B8FF34] sword icon: blade as yellow-green neon outline, near-black guard, diagonal, sprite on pure black"),
    ("default_tool_stoneaxe.png",     "[hue cool grey-blue #8FB8D8] axe icon: head as faint cool grey-blue neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_stonepick.png",    "[hue cool grey-blue #8FB8D8] pickaxe icon: head as faint grey-blue neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_stoneshovel.png",  "[hue cool grey-blue #8FB8D8] shovel icon: blade as faint grey-blue neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_stonesword.png",   "[hue cool grey-blue #8FB8D8] sword icon: blade as faint grey-blue neon outline, near-black guard, diagonal, sprite on pure black"),
    ("default_tool_diamondaxe.png",   "[hue icy #CFFAFF] axe icon: head as icy white-cyan neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_diamondpick.png",  "[hue icy #CFFAFF] pickaxe icon: head as icy white-cyan neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_diamondshovel.png","[hue icy #CFFAFF] shovel icon: blade as icy neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_diamondsword.png", "[hue icy #CFFAFF] sword icon: blade as icy white-cyan neon outline, near-black guard, diagonal, sprite on pure black"),
    ("default_tool_woodaxe.png",      "[hue amber #FFB347] axe icon: head as warm amber neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_woodpick.png",     "[hue amber #FFB347] pickaxe icon: head as warm amber neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_woodshovel.png",   "[hue amber #FFB347] shovel icon: blade as warm amber neon outline, near-black handle, diagonal, sprite on pure black"),
    ("default_tool_woodsword.png",    "[hue amber #FFB347] sword icon: blade as warm amber neon outline, near-black guard, diagonal, sprite on pure black"),
], "sprite")

# ---- B14 remaining sprites + HUD bits -------------------------------------------
sheet("B14_hud_misc", [
    ("_var_fire2.png",             "bright orange-glowing flame cluster, slightly different shape, sprite on pure black"),
    ("_var_torch2.png",            "hand torch flame frame: same torch with brighter, wider cyan-white flame, sprite on pure black"),
    ("default_chest_inside.png",   "dark interior wall of an open chest with faint amber glow edges, fills the whole square"),
    ("heart.png",                  "one small red-pink glowing heart symbol, sprite on pure black"),
    ("bubble.png",                 "one small cyan glowing bubble circle with highlight dot, sprite on pure black"),
    ("default_item_smoke.png",     "tiny pale grey-white glow puff, sprite on pure black"),
    ("gui_hotbar_selected.png",    "square HUD frame: bright cyan-glowing border box with small corner brackets, pure-black empty center, fills the square"),
    ("gui_hb_bg.png",              "square HUD slot background: very faint dark panel with thin dim grey-blue border, pure-black center, fills the square"),
    ("gui_furnace_arrow_bg.png",   "wide right-pointing arrow outline, dim grey-blue glow, thick, pure-black inside, fills the square"),
    ("gui_furnace_arrow_fg.png",   "wide right-pointing arrow filled with bright orange glow, fills the square"),
    ("_spare_glow.png",            "single small white-cyan glowing dot, sprite centered on pure black"),
    ("_spare_glow2.png",           "single small magenta glowing dot, sprite centered on pure black"),
    ("_spare_glow3.png",           "single small green glowing dot, sprite centered on pure black"),
    ("_spare_glow4.png",           "single small amber glowing dot, sprite centered on pure black"),
    ("_spare_glow5.png",           "single small violet glowing dot, sprite centered on pure black"),
    ("_spare_glow6.png",           "single small red glowing dot, sprite centered on pure black"),
], "sprite")
for t in ["default_chest_inside.png", "gui_hotbar_selected.png", "gui_hb_bg.png",
          "gui_furnace_arrow_bg.png", "gui_furnace_arrow_fg.png"]:
    B[t]["kind"] = "tilea"

# ---- M01 misc 3x3 (fern frames) ----------------------------------------------
sheet("M01_misc", [
    ("default_fern_2.png", "medium fern with glowing green fronds spread wide, sprite on pure black"),
    ("default_fern_3.png", "large lush fern with many glowing green fronds, sprite on pure black"),
    ("_unused_m01_1.png", "empty pure black cell"),
    ("_unused_m01_2.png", "empty pure black cell"),
    ("_unused_m01_3.png", "empty pure black cell"),
    ("_unused_m01_4.png", "empty pure black cell"),
    ("_unused_m01_5.png", "empty pure black cell"),
    ("_unused_m01_6.png", "empty pure black cell"),
    ("_unused_m01_7.png", "empty pure black cell"),
], "sprite")
# crack stages are drawn procedurally (see build_cracks), not generated

# ---- B15 corals, desert sandstone, strays ------------------------------------
sheet("B15_extras", [
    ("default_desert_sandstone.png",        "dark rust-orange sandstone slab tile with faint glowing strata lines"),
    ("default_desert_sandstone_block.png",  "rust sandstone panel tile with orange border grid"),
    ("default_desert_sandstone_brick.png",  "rust bricks with orange glowing mortar lines"),
    ("default_coral_brown.png",             "brain coral tile: dark olive-brown coral surface with amber glowing polyp dots"),
    ("default_coral_cyan.png",              "coral tile: dark teal surface with bright cyan glowing polyp dots"),
    ("default_coral_green.png",             "coral tile: dark green surface with neon green glowing polyp dots"),
    ("default_coral_orange.png",            "coral tile: dark rust surface with bright orange glowing polyp dots"),
    ("default_coral_pink.png",              "coral tile: dark maroon surface with neon pink glowing polyp dots"),
    ("default_coral_skeleton.png",          "bleached coral tile: pale white-grey surface with soft white glowing cracks"),
    ("default_blueberry_overlay.png",       "several tiny bright blue glowing berry dots on pure black empty background"),
    ("default_fence_rail_overlay.png",      "neutral grey-white glowing thin fence rails overlay, sprite on pure black"),
    ("default_gold_ingot.png",              "stacked ingot bars glowing bright yellow, sprite on pure black"),
    ("_var_water3.png",                     "third frame of flowing water: dark blue liquid with glowing cyan wave lines shifted again, fills the whole square"),
    ("_var_river3.png",                     "third frame of river water with shifted turquoise wave lines, fills the whole square"),
    ("_var_lava3.png",                      "third frame of lava crust with shifted orange crack veins, fills the whole square"),
    ("_var_torch3.png",                     "hand torch flame frame: same torch with a smaller, intense white-hot flame, sprite on pure black"),
], "tile")
for t in ["default_blueberry_overlay.png", "default_fence_rail_overlay.png", "default_gold_ingot.png",
          "_var_torch3.png"]:
    B[t]["kind"] = "sprite"
for t in ["_var_water3.png", "_var_river3.png", "_var_lava3.png"]:
    B[t]["kind"] = "tilea"

# Odd-size originals keep their native resolution (HUD sprites / detailed plants).
B["heart.png"]["size"] = (12, 12)
B["bubble.png"]["size"] = (12, 12)
B["default_item_smoke.png"]["size"] = (8, 8)
B["default_fern_2.png"]["size"] = (32, 32)
B["default_fern_3.png"]["size"] = (32, 32)

# ---- C01 dedicated chest sheet (2x2, full fidelity) ---------------------------
C01_CELLS = [
    ("default_chest_front.png", "[hue amber #FFB347] storage chest FRONT face: near-black wood panel, thin amber neon frame, one small bright cyan neon latch rectangle in the center top, seamless tile"),
    ("default_chest_side.png",  "[hue amber #FFB347] storage chest SIDE face: near-black wood panel, thin amber neon frame, seamless tile"),
    ("default_chest_top.png",   "[hue amber #FFB347] storage chest LID TOP: near-black panel, thin amber neon border, seamless tile"),
    ("default_chest_inside.png","[hue amber #FFB347] open chest interior: near-black walls with faint amber neon edge glow, full square"),
]
for i, (tex, desc) in enumerate(C01_CELLS):
    B[tex] = dict(sheet="C01_chest", cell=i, kind="tile", size=(16, 16), desc=desc)

# ---- P01 semi-transparent plate pair (triangulation matte) ---------------------
# Sheet layout: LEFT half pure black background, RIGHT half pure white background,
# each half a 2x2 grid of the same four wireframe sprites. Alpha is triangulated
# from the plate pair: A = 1 - (W - B) / 255, RGB = B / A (premultiplied solve),
# the method used by the Seirin art pipeline (ai_agent_docs/ART_PIPELINE_NEXT.md).
SEMI = {
    "default_water.png":         0,
    "default_river_water.png":   1,
    "default_glass.png":         2,
    "default_obsidian_glass.png": 3,
}
SEMI_DESC = [
    "water surface: three thin horizontal cyan neon wave lines with small gaps, centered",
    "river water surface: three thin horizontal turquoise neon wave lines with small gaps",
    "glass pane: one square cyan neon frame with a single diagonal streak, empty center",
    "glass pane: one square violet neon frame with a single diagonal streak, empty center",
]

# Variants/spares are internal, not shipped.# Variants/spares are internal, not shipped.
INTERNAL = set(n for n in B if n.startswith("_"))

# Dedicated full-sheet generations: file -> (sheet name, description)
DEDICATED = {
    "gui_formbg.png": ("D01_formbg",
        "A dark cyberpunk interface background: near-black deep navy field with a fine thin glowing cyan grid of squares, "
        "subtle violet glow gradient in one corner, faint scanlines, clean minimal synthwave terminal aesthetic. "
        "The grid covers the entire canvas edge to edge. No text, no logos, no objects."),
    "gui_hotbar.png": ("D02_hotbar",
        "A single horizontal HUD hotbar strip spanning the full width of the canvas, vertically centered: a dark near-black bar "
        "with eight empty square slots outlined by thin glowing cyan neon frames, small corner accents, subtle outer glow. "
        "Everything above and below the bar is pure solid black empty space. No icons, no text, no numbers."),
    "default_furnace_front_new.png": ("D03_furnace_new",
        "Front view of a cyberpunk industrial furnace appliance: dark graphite metal body with thin glowing cyan panel lines, "
        "an arched fire door in the lower center glowing intense orange like lava, small status lights, dark vents. "
        "Slightly wider than tall composition, centered, on a pure black background. No text."),
}

# Animated strips assembled from processed stills (file -> builder spec)
ANIMATED = {
    # water/glass come from the triangulated P01 plates; water anim = roll of ONE
    # base texture (no variant sprites -> stable color); torch anim = ONE torch,
    # flame-only brightness flicker (same torch, same colors every frame).
    "default_water_source_animated.png":        dict(base="default_water.png",  frames=16, style="water", alpha_scale=0.85),
    "default_water_flowing_animated.png":       dict(base="default_water.png",  frames=16, style="flow",  alpha_scale=0.85),
    "default_river_water_source_animated.png":  dict(base="default_river_water.png", frames=16, style="water", alpha_scale=0.85),
    "default_river_water_flowing_animated.png": dict(base="default_river_water.png", frames=16, style="flow",  alpha_scale=0.85),
    "default_lava_source_animated.png":         dict(base="default_lava.png",   frames=8,  style="water", alpha_scale=1.0, speed=0.5, variants=["lava2", "lava3"]),
    "default_lava_flowing_animated.png":        dict(base="default_lava.png",   frames=16, style="flow",  alpha_scale=1.0, speed=0.5),
        "default_torch_animated.png":               dict(base="default_torch_on_floor.png", frames=16, style="torch", alpha_scale=1.0),
    "default_torch_on_floor_animated.png":      dict(base="default_torch_on_floor.png", frames=16, style="torch", alpha_scale=1.0),
    "default_torch_on_ceiling_animated.png":    dict(base="default_torch_on_floor.png", frames=16, style="torch", alpha_scale=1.0, flip=True),    "default_river_water_flowing_animated.png": dict(base="default_river_water.png", frames=16, style="flow",  alpha_scale=0.62, variants=["river2", "river3"]),
    "default_lava_source_animated.png":         dict(base="default_lava.png",   frames=8,  style="water", alpha_scale=1.0, speed=0.5, variants=["lava2", "lava3"]),
    "default_lava_flowing_animated.png":        dict(base="default_lava.png",   frames=16, style="flow",  alpha_scale=1.0, speed=0.5),
        "default_furnace_front_active.png":         dict(base="default_furnace_front.png", frames=8, style="furnace", alpha_scale=1.0),
    "crack_anylength.png":                      dict(style="crackstack"),  # built from crack_anylength_s*.png
}

# ---------------------------------------------------------------- prompts --

STYLE = (
    "Strict two-tone NEON pixel art: a deep black field (#050810) plus EXACTLY ONE saturated "
    "neon hue per texture (the hue named in brackets). Everything is drawn as thin glowing neon "
    "wireframe lines, circuit traces or laser holograms, Tron light-cycle style. Fills are FLAT "
    "near-black tinted with the same hue (brightness under 22%), never mid-grey. No gradients "
    "except a 1px dim halo hugging a neon line, no white fills, no secondary hues, no realistic "
    "shading, no photo texture."
)

LATTICE = (
    "Strict pixel-art lattice: every texture is 16x16 logical pixels; each logical pixel is one "
    "solid square block of uniform color with crisp hard edges (chunky 16-bit look). Neon lines "
    "are 1 logical pixel thick, fully saturated and bright. No anti-aliasing blur between "
    "logical pixels, no dithering, no noise."
)

def build_prompt(sheet_name):
    cells = sorted((c for c in B.values() if c["sheet"] == sheet_name), key=lambda c: c["cell"])
    n = len(cells)
    cols = 3 if sheet_name.startswith("M01") else 4
    rows = (n + cols - 1) // cols
    kinds = set(c["kind"] for c in cells)
    layout = []
    if "sprite" in kinds:
        layout.append(
            f"Layout: a perfect {cols}x{rows} grid of square cells on a 1024x1024 canvas. "
            "Each cell contains ONE small sprite centered in the middle 75% of the cell, floating "
            "on PURE SOLID BLACK (#000000) empty background. No boxes or frames around sprites, "
            "no gaps between cells, no labels, no text, no numbers, no watermark."
        )
    if "tile" in kinds or "tilea" in kinds:
        layout.append(
            f"Layout: a perfect {cols}x{rows} grid of square seamless tiles on a 1024x1024 canvas, "
            "tiles directly abutting edge to edge, NO gaps, NO separating lines, NO labels, no text, "
            "no watermark. Each tile fills its cell completely so it can repeat seamlessly."
            + (" Some tiles have small pure-black holes between shapes (they become transparency)." if "tilea" in kinds else "")
        )
    order = []
    for r in range(rows):
        rowcells = cells[r * cols:(r + 1) * cols]
        order.append("Row %d: %s" % (r + 1, " | ".join(
            "[%d] %s" % (i + 1, c["desc"]) for i, c in enumerate(rowcells))))
    return "%s\n%s\n%s\n%s" % (STYLE, LATTICE, "\n".join(layout), "\n".join(order))

# ---------------------------------------------------------------- helpers --

def load_sheet(name):
    p = os.path.join(SHEETS_DIR, name + ".png")
    im = Image.open(p).convert("RGBA")
    if im.size != (1024, 1024):
        print("WARNING: sheet %s is %s (expected 1024x1024); stretching to grid" % (name, im.size))
        im = im.resize((1024, 1024), Image.LANCZOS)
    return im

def cell_rect(sheet_name, idx):
    if sheet_name.startswith("C01"):
        cols, rows = 2, 2
    elif sheet_name.startswith("M01"):
        cols, rows = 3, 3
    else:
        cols, rows = 4, 4
    cw, ch = 1024 / cols, 1024 / rows

    x0, y0 = int(round(idx % cols * cw)), int(round(idx // cols * ch))
    return x0, y0, int(round(cw)), int(round(ch))

def key_alpha(im, lo=14, hi=88):
    """Pure black -> transparent, bright neon -> opaque (soft key)."""
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            v = max(r, g, b)
            k = (v - lo) / float(hi - lo)
            if k < 0: k = 0.0
            elif k > 1: k = 1.0
            op[x, y] = (r, g, b, int(round(255 * k)))
    return out

def alpha_scale(im, s):
    a = im.getchannel("A").point(lambda v: int(v * s))
    im.putalpha(a)
    return im

def semi_from_pair(sheet_im, idx, name):
    """Triangulation matte from a black plate and a white plate (Seirin method):
    W = F*a + (1-a)*255, B = F*a  ->  a = 1 - (W - B)/255, F = B/a."""
    cw = 256
    x0, y0 = (idx % 2) * cw, (idx // 2) * cw
    ins = 20
    b_plate = sheet_im.crop((x0 + ins, y0 + ins, x0 + cw - ins, y0 + cw - ins)).convert("RGB")
    w_plate = sheet_im.crop((512 + x0 + ins, y0 + ins, 512 + x0 + cw - ins, y0 + cw - ins)).convert("RGB")
    W, H = b_plate.size
    bp, wp = b_plate.load(), w_plate.load()
    out = Image.new("RGBA", (W, H))
    op = out.load()
    # structural check: bright regions of both plates must roughly agree
    # black plate: neon lines are the bright pixels; white plate: neon lines are
    # pixels that deviate from pure white in at least one channel
    mb = set((x, y) for y in range(H) for x in range(W) if max(bp[x, y]) > 90)
    mw = set((x, y) for y in range(H) for x in range(W) if 255 - min(wp[x, y]) > 60)
    inter = len(mb & mw)
    iou = inter / max(1, len(mb | mw))
    if iou < 0.45:
        print("WARNING: %s plate pair misaligned (IoU %.2f), falling back to keying" % (name, iou))
        small = b_plate.resize((16, 16), Image.BOX)
        return key_alpha(small, 14, 88)
    for y in range(H):
        for x in range(W):
            rB, gB, bB = bp[x, y]
            rW, gW, bW = wp[x, y]
            a = 1.0 - ((rW - rB) + (gW - gB) + (bW - bB)) / (3.0 * 255.0)
            a = max(0.0, min(1.0, a))
            a = int(round(a * 8)) / 8.0          # quantize plate noise away
            if a < 0.25:
                a = 0.0
            elif a > 0.92:
                a = 1.0
            if a <= 0.0:
                op[x, y] = (0, 0, 0, 0)
            else:
                r = min(255, int(round(rB / a)))
                g = min(255, int(round(gB / a)))
                b = min(255, int(round(bB / a)))
                op[x, y] = (r, g, b, int(round(a * 255)))
    return out.resize((16, 16), Image.BOX)


def _neon_hue(im):
    """Circular mean hue of the saturated bright pixels (the neon lines)."""
    import colorsys, math
    sx = sy = nx = 0.0
    n = 0
    px = im.convert("RGBA").load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 80:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s > 0.35 and v > 0.35:
                ang = h * 2 * math.pi
                sx += math.cos(ang); sy += math.sin(ang); n += 1
    if not n:
        return None
    return (math.atan2(sy, sx) / (2 * math.pi)) % 1.0


def _set_hue(im, hue, rows=None):
    """Recolor saturated bright pixels (optionally only in the top N rows) to hue."""
    import colorsys
    px = im.load()
    ymax = im.height if rows is None else rows
    for y in range(ymax):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 60:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s > 0.25 and v > 0.30:
                r, g, b = colorsys.hsv_to_rgb(hue, s, v)
                px[x, y] = (int(r * 255), int(g * 255), int(b * 255), a)
    return im


def unify_hues():
    """Make side strips use exactly the same neon hue as their top textures."""
    pairs = [
        ("default_grass_side.png", "default_grass.png"),
        ("default_dry_grass_side.png", "default_dry_grass.png"),
        ("default_snow_side.png", "default_snow.png"),
        ("default_moss_side.png", "default_moss.png"),
        ("default_coniferous_litter_side.png", "default_coniferous_litter.png"),
        ("default_rainforest_litter_side.png", "default_rainforest_litter.png"),
        ("default_stones_side.png", "default_stones.png"),
    ]
    for side, top in pairs:
        sp, tp = os.path.join(TEXDIR, side), os.path.join(TEXDIR, top)
        if not (os.path.exists(sp) and os.path.exists(tp)):
            continue
        hue = _neon_hue(Image.open(tp))
        if hue is None:
            print("skip %s (no neon found in top)" % side)
            continue
        im = Image.open(sp).convert("RGBA")
        _set_hue(im, hue, rows=5)
        im.save(sp, optimize=True)
        print("unified %-38s hue=%.2f" % (side, hue))


def build_cracks():
    """5 crack stages, procedural: bright neon cracks with real alpha, so they
    show over translucent glass (not just its opaque frame)."""
    import random
    rng = random.Random(4242)
    stages = []
    lines_by_stage = [2, 4, 6, 9, 13]
    walks = []
    for i in range(13):                     # pre-generate all crack walks
        x, y = 8 + rng.randint(-2, 2), 8 + rng.randint(-2, 2)
        pts = [(x, y)]
        dx, dy = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)])
        for _ in range(rng.randint(6, 12)):
            x = max(0, min(15, x + dx)); y = max(0, min(15, y + dy))
            pts.append((x, y))
            if rng.random() < 0.35:
                dx, dy = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)])
        walks.append(pts)
    for si, nlines in enumerate(lines_by_stage):
        im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        op = im.load()
        for pts in walks[:nlines]:
            for (x, y) in pts:
                op[x, y] = (190, 250, 255, 235)
                for nx, ny in ((x + 1, y), (x, y + 1), (x + 1, y + 1)):
                    if 0 <= nx < 16 and 0 <= ny < 16 and op[nx, ny][3] == 0:
                        op[nx, ny] = (90, 190, 210, 110)
        stages.append(im)
    return stages


def process():
    os.makedirs(SHEETS_DIR, exist_ok=True)
    os.makedirs(os.path.join(SHEETS_DIR, "derived"), exist_ok=True)
    stats = []
    sheets = set(c["sheet"] for c in B.values()) | set(SEMI and ["P01_semis"] or []) | set(s for s, _d in DEDICATED.values())
    missing = [s for s in sorted(sheets)
               if not os.path.exists(os.path.join(SHEETS_DIR, s + ".png"))]
    if missing:
        print("skipping (sheets not generated yet): %s" % ", ".join(missing))
    done_sheets = sheets - set(missing)
    sheet_cache = {}
    for name, c in sorted(B.items()):
        if name in SEMI:
            # semi-transparent textures come from the P01 plate pair (triangulated)
            if "P01_semis" in done_sheets:
                if "P01_semis" not in sheet_cache:
                    sheet_cache["P01_semis"] = load_sheet("P01_semis")
                semi = semi_from_pair(sheet_cache["P01_semis"], SEMI[name], name)
                semi.save(os.path.join(TEXDIR, name), optimize=True)
                a = semi.getchannel("A")
                stats.append((name, "P01_semis", SEMI[name],
                              round(100 * sum(1 for v in a.tobytes() if v > 8) / 256)))
            else:
                print("skipping %s (P01_semis.png not generated)" % name)
            continue
        if c["sheet"] not in done_sheets:
            continue
        if name in INTERNAL and not name.startswith(("_var_", "crack_anylength_s")):
            continue  # spares not shipped as files; variants stored below
        p = os.path.join(TEXDIR, name)
    for name, c in sorted(B.items()):
        if c["sheet"] not in done_sheets:
            continue
        if name in INTERNAL and not name.startswith(("_var_", "crack_anylength_s")):
            continue  # spares not shipped as files; variants stored below
        p = os.path.join(TEXDIR, name)
        if name.startswith("_"):
            p = os.path.join(SHEETS_DIR, "derived", name)
        if c["sheet"] not in sheet_cache:
            sheet_cache[c["sheet"]] = load_sheet(c["sheet"])
        sheet_im = sheet_cache[c["sheet"]]
        x0, y0, cw, ch = cell_rect(c["sheet"], c["cell"])
        inset = 16 if c["kind"] == "sprite" and c["sheet"] != "M01_misc" else 0
        if c["sheet"] == "M01_misc":
            inset = 24 if c["kind"] == "sprite" else 0
        cell = sheet_im.crop((x0 + inset, y0 + inset, x0 + cw - inset, y0 + ch - inset))
        tw, th = c["size"]
        if c["kind"] == "sprite":
            # trim to content bbox (kills stray border frames), pad back to square
            cell = key_alpha(cell)
            bbox = cell.getbbox()
            if bbox:
                cell = cell.crop(bbox)
            side = max(cell.size)
            sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            sq.paste(cell, ((side - cell.width) // 2, (side - cell.height) // 2), cell)
            cell = sq
        small = cell.resize((tw, th), Image.BOX)
        if c["kind"] in ("sprite", "tilea"):
            small = key_alpha(small)
        if small.mode != "RGBA":
            small = small.convert("RGBA")
        small.save(p, optimize=True)
        a = small.getchannel("A")
        stats.append((name, c["sheet"], c["cell"], round(100 * sum(1 for v in a.tobytes() if v > 8) / (tw * th))))
    # dedicated sheets
    for name, (sheet_name, _desc) in DEDICATED.items():
        if sheet_name not in done_sheets:
            continue
        sheet_im = load_sheet(sheet_name)
        if name == "gui_formbg.png":
            out = sheet_im.resize((496, 506), Image.BOX)
        elif name == "gui_hotbar.png":
            grey = sheet_im.convert("L")
            rows = [y for y in range(1024) if max(grey.crop((0, y, 1024, y + 1)).getextrema()) > 24]
            if rows:
                y0, y1 = min(rows), max(rows) + 1
                pad = int((y1 - y0) * 0.12)
                y0, y1 = max(0, y0 - pad), min(1024, y1 + pad)
            else:
                y0, y1 = 430, 594
            band = sheet_im.crop((0, y0, 1024, y1))
            out = band.resize((596, 78), Image.BOX)
        elif name == "default_furnace_front_new.png":
            band = sheet_im.crop((0, 170, 1024, 854))  # 1024x684 center band
            out = band.resize((512, 341), Image.BOX)
        out.save(os.path.join(TEXDIR, name), optimize=True)
        stats.append((name, sheet_name, -1, -1))
    with open(os.path.join(SHEETS_DIR, "process_stats.json"), "w") as f:
        json.dump(stats, f, indent=1)
    print("processed %d textures" % len(stats))
    for s in stats:
        cov = "%d%%" % s[3] if s[3] >= 0 else "-"
        print("  %-46s %-22s cell %02d  coverage=%s" % (s[0], s[1], s[2], cov))

# ------------------------------------------------------------- animation --

def _roll_rows(im, shift_fn):
    """Horizontal per-row integer roll (wrap keeps tile seamless)."""
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", im.size)
    op = out.load()
    for y in range(h):
        s = shift_fn(y) % w
        for x in range(w):
            op[(x + s) % w, y] = px[x, y]
    return out

def _modulate(im, f):
    """Brightness pulse factor f in [0..1] -> scale around 0.9..1.1."""
    k = 0.9 + 0.25 * f
    return Image.eval(im, lambda v: min(255, int(v * k))) if im.mode == "RGB" else Image.merge(
        "RGBA", [Image.eval(ch, lambda v: min(255, int(v * k))) for ch in im.split()])

def build_frames(base_img, frames, style, speed=1.0, flip=False, variants=None):
    frames_out = []
    base = base_img.convert("RGBA")
    if flip:
        base = base.transpose(Image.FLIP_TOP_BOTTOM)
    variants = [v.convert("RGBA") for v in (variants or [])]
    cyc = [base] + variants
    w, h = base.size
    for i in range(frames):
        src = cyc[i * len(cyc) // frames % len(cyc)]
        t = 2 * math.pi * i / frames * (speed if speed else 1.0)
        if style in ("water", "flow"):
            amp = 1.6 if style == "water" else 2.6
            per = 4 if style == "water" else 3
            fr = _roll_rows(src, lambda y, t=t, amp=amp, per=per:
                            int(round(amp * math.sin(2 * math.pi * y / per + t))))
            fr = _modulate(fr, 0.5 + 0.5 * math.sin(t * 2))
        elif style == "torch":
            fr = src.copy()
            px = fr.load()
            # flicker the flame region (top third of the sprite)
            fl = 0.75 + 0.25 * math.sin(t * 3.0) * math.cos(t * 1.7)
            for y in range(0, h // 3 + 1):
                for x in range(w):
                    r, g, b, a = px[x, y]
                    px[x, y] = (int(r * fl), int(g * fl), int(b * fl), a)
        elif style == "furnace":
            fr = src.copy()
            px = fr.load()
            gl = 0.6 + 0.4 * math.sin(t)
            for y in range(h * 8 // 16, h * 13 // 16):     # fire mouth band
                for x in range(w * 3 // 16, w * 13 // 16):
                    r, g, b, a = px[x, y]
                    px[x, y] = (min(255, int(r + 190 * gl)), int(g + 90 * gl), int(b * 0.8 + 30 * gl), a)
        else:
            fr = src.copy()
        frames_out.append(fr)
    return frames_out

def vstack(frames):
    w = frames[0].width
    out = Image.new("RGBA", (w, sum(f.height for f in frames)))
    y = 0
    for f in frames:
        out.paste(f, (0, y)); y += f.height
    return out

def assemble():
    # invisible node overlay: deterministic faint corner brackets (AI renders it too faint)
    ovl = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    op = ovl.load()
    for x, y in [(0, 0), (15, 0), (0, 15), (15, 15)]:
        for dx, dy in [(0, 0), (1, 0), (0, 1)]:
            op[min(15, x + dx), min(15, y + dy)] = (200, 230, 255, 90)
    ovl.save(os.path.join(TEXDIR, "default_invisible_node_overlay.png"), optimize=True)
    for name, spec in ANIMATED.items():
        p = os.path.join(TEXDIR, name)
        if spec["style"] == "crackstack":
            out = vstack(build_cracks())
        else:
            base = Image.open(os.path.join(TEXDIR, spec["base"])).convert("RGBA")
            variants = []
            vdir = os.path.join(SHEETS_DIR, "derived")
            for vn in spec.get("variants", []):
                q = os.path.join(vdir, "_var_%s.png" % vn)
                if os.path.exists(q):
                    variants.append(Image.open(q))
            frames = build_frames(base, spec["frames"], spec["style"],
                                  speed=spec.get("speed", 1.0), flip=spec.get("flip", False),
                                  variants=variants)
            out = vstack(frames)
            if spec.get("alpha_scale", 1.0) != 1.0:
                out = alpha_scale(out, spec["alpha_scale"])
        if name in ("default_lava_source_animated.png", "default_lava_flowing_animated.png",
                    "default_furnace_front_active.png"):
            out = Image.merge("RGBA", list(out.split()[:3]) + [Image.new("L", out.size, 255)])
        out.save(p, optimize=True)
        print("assembled %s (%s)" % (name, out.size))

# --------------------------------------------------------------- polish --

# Sprites the model rendered as plain white/grey — retint toward their intended hue.
TINT = {
    "default_clay_lump.png": (212, 190, 255),   # violet-grey clay
    "default_flint.png": (198, 214, 255),       # cool blue-grey flint
    "default_tin_lump.png": (205, 220, 255),    # silvery pale-blue tin
}

def fix_glass():
    """Redraw the glass panes as a clean thin neon frame + diagonal streak,
    keeping the hue triangulated from the P01 plates."""
    for name in ("default_glass.png", "default_obsidian_glass.png"):
        p = os.path.join(TEXDIR, name)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        px = [q for q in im.getdata() if q[3] > 120]
        if not px:
            continue
        r = sum(q[0] for q in px) // len(px)
        g = sum(q[1] for q in px) // len(px)
        b = sum(q[2] for q in px) // len(px)
        out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        op = out.load()
        for i in range(16):
            for j, (x, y) in enumerate(((i, 0), (i, 15), (0, i), (15, i))):
                op[x, y] = (r, g, b, 235)
            # dim inner halo
            if 0 < i < 15:
                for x, y in ((i, 1), (i, 14), (1, i), (14, i)):
                    if op[x, y][3] == 0:
                        op[x, y] = (r, g, b, 70)
        for i in range(9):                       # diagonal highlight streak
            x, y = 12 - i, 2 + i
            op[x, y] = (r, g, b, 165)
            if 0 <= x - 1 < 16:
                op[x - 1, y] = (r, g, b, 80)
        out.save(p, optimize=True)
        print("glass redrawn %-28s rgb=(%d,%d,%d)" % (name, r, g, b))


def polish():
    """Second-pass fixes over processed files:
    - opaque tiles whose glow lines came out too faint get a brightness lift
      (fills stay deep dark, neon lines become properly visible);
    - white item sprites listed in TINT get hue-tinted."""
    from PIL import ImageStat
    for name, c in sorted(B.items()):
        p = os.path.join(TEXDIR, name)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        changed = False
        if c["kind"] == "tile":
            vals = sorted(max(px[:3]) for px in im.getdata() if px[3] > 128)
            if vals:
                p95 = vals[int(len(vals) * 0.95) - 1]
                if p95 < 110:                      # glow lines too faint
                    k = min(3.0, 170.0 / max(p95, 1))
                    r, g, b = [ch.point(lambda v: min(255, int(v * k))) for ch in im.split()[:3]]
                    im = Image.merge("RGBA", (r, g, b, im.getchannel("A")))
                    changed = True
                    print("lift %-38s p95=%d k=%.2f" % (name, p95, k))
        if name in TINT:
            tr, tg, tb = TINT[name]
            px = im.load()
            for y in range(im.height):
                for x in range(im.width):
                    r, g, b, a = px[x, y]
                    if a > 64 and max(r, g, b) > 110 and (max(r, g, b) - min(r, g, b)) < 60:
                        px[x, y] = (r * tr // 255, g * tg // 255, b * tb // 255, a)
            changed = True
            print("tint %s" % name)
        if changed:
            im.save(p, optimize=True)
    print("polish done")

# ------------------------------------------------------------------ main --

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "process"
    if cmd == "prompts":
        names = sorted(set(c["sheet"] for c in B.values()))
        for n in names:
            print("=" * 20, n, "=" * 20)
            print(build_prompt(n))
            print()
        p01 = ("%s\n%s\nLayout: the canvas is split into two vertical halves. LEFT half: PURE SOLID BLACK "
               "background. RIGHT half: PURE SOLID WHITE background. On each half the SAME 2x2 grid of "
               "four wireframe sprites, pixel-identical in shape and color on both halves, centered in "
               "their quadrant, thin glowing lines only: [1] %s | [2] %s | [3] %s | [4] %s. "
               "Only the background differs between the halves. No frames around sprites, no labels, "
               "no text, no watermark." % (STYLE, LATTICE, SEMI_DESC[0], SEMI_DESC[1], SEMI_DESC[2], SEMI_DESC[3]))
        print("=" * 20, "P01_semis", "=" * 20)
        print(p01)
        print()
        for name, (s, d) in DEDICATED.items():
            print("=" * 20, s, "=" * 20)
            print(d)
            print()
    elif cmd == "check":
        have = set(os.listdir(TEXDIR))
        planned = set(B) - INTERNAL | set(DEDICATED) | set(ANIMATED)
        print("files on disk:", len(have))
        print("planned:      ", len(planned))
        miss = sorted(planned - have)
        extra = sorted(have - planned - {"crack_anylength_s1.png"})
        print("missing from plan:", miss)
        print("on disk but not planned:", extra)
    elif cmd == "process":
        process()
    elif cmd == "polish":
        fix_glass()
        polish()
    elif cmd == "unify":
        unify_hues()
    elif cmd == "polish":
        fix_glass()
        polish()
    elif cmd == "assemble":
        assemble()
    else:
        print(__doc__)

if __name__ == "__main__":
    main()
