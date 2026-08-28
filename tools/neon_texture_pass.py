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
    ("default_stone.png",             "dark graphite stone panel tile with a faint thin cyan-blue wire grid and subtle diagonal chisel marks"),
    ("default_cobble.png",            "irregular rounded cobblestone cells outlined with pale cyan glow on dark graphite, seamless tile"),
    ("default_mossycobble.png",       "cobblestone cells with neon green glowing moss filling the joints, seamless tile"),
    ("default_stone_brick.png",       "two rows of offset bricks, thin glowing cyan mortar lines on dark graphite, seamless tile"),
    ("default_stone_block.png",       "smooth dark slab tile, single hairline cyan border and one faint inner cross seam"),
    ("default_gravel.png",            "scatter of small pebbles outlined in pale blue-white glow on near-black, dense seamless tile"),
    ("default_sand.png",              "dark sand tile with dotted amber scan-line ripples, subtle dune curves"),
    ("default_silver_sand.png",       "pale blue-white glowing speckle field on blue-black, seamless tile"),
    ("default_clay.png",              "smooth dull violet-grey clay tile with faint purple tracery lines"),
    ("default_dirt.png",              "dark brown-black soil tile with sparse tiny amber specks"),
    ("default_dry_dirt.png",          "cracked dark earth tile, thin glowing orange crack lines branching across"),
    ("default_permafrost.png",        "blue-black frozen soil tile with tiny pale ice-crystal glints"),
    ("default_grass.png",             "dark green-black turf tile with a crisp neon green grid of grass blades, seamless"),
    ("default_dry_grass.png",         "olive-black turf tile with sparse amber-yellow glowing grass grid"),
    ("default_snow.png",              "near-black frost tile with a delicate white-blue glitter lattice"),
    ("default_ice.png",               "deep navy translucent ice tile with glowing white-blue fracture lines"),
], "tile")

# ---- B02 desert / sandstone / obsidian --------------------------------------
sheet("B02_desert_obsidian", [
    ("default_desert_sand.png",           "dark rust-red sand tile with orange glowing scan ripples"),
    ("default_desert_cobble.png",         "warm red-brown cobble cells with orange glow joints, seamless tile"),
    ("default_desert_stone.png",          "dark maroon stone panel with faint red wire grid"),
    ("default_desert_stone_block.png",    "smooth maroon slab with red hairline border"),
    ("default_desert_stone_brick.png",    "maroon bricks with glowing red mortar lines"),
    ("default_sandstone.png",             "dark amber slab tile with faint horizontal glowing strata lines"),
    ("default_sandstone_block.png",       "neat amber panel tile with warm gold border grid"),
    ("default_sandstone_brick.png",       "amber bricks with warm gold glowing mortar"),
    ("default_silver_sandstone.png",      "cool blue slab tile with ice-white border grid"),
    ("default_silver_sandstone_block.png","smooth blue-grey panel with pale blue hairline frame"),
    ("default_silver_sandstone_brick.png","blue-grey bricks with ice-blue glowing mortar"),
    ("default_obsidian.png",              "near-black violet obsidian tile with deep purple wire grid"),
    ("default_obsidian_block.png",        "black slab tile with violet border glow"),
    ("default_obsidian_brick.png",        "dark violet bricks with purple glowing mortar"),
    ("default_moss.png",                  "neon green fuzzy moss patch glow on dark surface, seamless tile"),
    ("default_cloud.png",                 "soft white-blue glowing voxel cloud puffs with faint cyan grid on dark slate, seamless tile"),
], "tile")

# ---- B03 sides, litter, ground overlays --------------------------------------
sheet("B03_sides_overlays", [
    ("default_grass_side.png",              "side of a soil block: dark soil with a glowing neon green strip along the very top edge, tile"),
    ("default_dry_grass_side.png",          "soil block side with amber-yellow glow strip along the top edge, tile"),
    ("default_snow_side.png",               "soil block side with white-blue glow strip along the top edge, tile"),
    ("default_moss_side.png",               "stone block side with neon green dripping glow veins from the top edge, tile"),
    ("default_stones_side.png",             "soil block side with a few small glowing pale pebbles embedded near the top edge, small pure-black gaps elsewhere"),
    ("default_stones.png",                  "a few small glowing pale-blue pebbles scattered on pure black empty background"),
    ("default_coniferous_litter.png",       "dark pine forest floor tile with tiny glowing teal needles scattered"),
    ("default_coniferous_litter_side.png",  "soil side with a thin teal needle fringe glowing along the top edge, small pure-black gaps"),
    ("default_rainforest_litter.png",       "dark humus floor tile with tiny green-gold glowing specks"),
    ("default_rainforest_litter_side.png",  "soil side with green glowing fringe along the top edge, small pure-black gaps"),
    ("default_footprint.png",               "one glowing cyan boot footprint outline on pure black empty background"),
    ("default_invisible_node_overlay.png",  "four tiny faint white corner brackets near the edges on pure black empty background"),
    ("default_papyrus.png",                 "three tall green neon reeds with glowing stems on pure black"),
    ("default_kelp.png",                    "one tall wavy green neon seaweed strand with small leaflets on pure black"),
    ("default_glass_detail.png",            "a few tiny cyan sparkle glints scattered on pure black empty background"),
    ("default_obsidian_glass_detail.png",   "a few tiny violet sparkle glints scattered on pure black empty background"),
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
    ("default_wood.png",                 "oak planks tile: dark amber boards with thin glowing warm seams, horizontal"),
    ("default_junglewood.png",           "jungle planks tile: dark magenta-brown boards with glowing magenta seams"),
    ("default_pine_wood.png",            "pine planks tile: dark teal boards with glowing teal seams"),
    ("default_aspen_wood.png",           "aspen planks tile: pale dark boards with glowing pale cyan seams"),
    ("default_acacia_wood.png",          "acacia planks tile: dark red-orange boards with glowing orange seams"),
    ("default_fence_wood.png",           "one vertical amber-glowing fence post with two horizontal rails, sprite on pure black"),
    ("default_fence_junglewood.png",     "vertical fence post with rails glowing magenta, sprite on pure black"),
    ("default_fence_pine_wood.png",      "vertical fence post with rails glowing teal, sprite on pure black"),
    ("default_fence_aspen_wood.png",     "vertical fence post with rails glowing pale cyan, sprite on pure black"),
    ("default_fence_acacia_wood.png",    "vertical fence post with rails glowing red-orange, sprite on pure black"),
    ("default_fence_rail_wood.png",      "two thin horizontal glowing amber rails with small posts, sprite on pure black"),
    ("default_fence_rail_junglewood.png","two thin horizontal rails glowing magenta with small posts, sprite on pure black"),
    ("default_fence_rail_pine_wood.png", "two thin horizontal rails glowing teal with small posts, sprite on pure black"),
    ("default_fence_rail_aspen_wood.png","two thin horizontal rails glowing pale cyan with small posts, sprite on pure black"),
    ("default_fence_rail_acacia_wood.png","two thin horizontal rails glowing red-orange with small posts, sprite on pure black"),
    ("default_fence_overlay.png",        "neutral grey-white glowing fence rails overlay shape, sprite on pure black"),
], "sprite")
for t in ["default_wood.png", "default_junglewood.png", "default_pine_wood.png",
          "default_aspen_wood.png", "default_acacia_wood.png"]:
    B[t]["kind"] = "tile"

# ---- B06 leaves (alpha tiles) ---------------------------------------------------
sheet("B06_leaves", [
    ("default_leaves.png",                "dense oak canopy tile, dark emerald leaf clusters outlined by a neon green vein web, small pure-black gaps between clusters, fills the whole square"),
    ("default_leaves_simple.png",         "sparse neon green leaf vein web tile with larger pure-black gaps, fills the square"),
    ("default_jungleleaves.png",          "dense jungle canopy tile with magenta and teal glowing veins, small pure-black gaps"),
    ("default_jungleleaves_simple.png",   "sparse jungle canopy web, magenta glow, larger gaps"),
    ("default_pine_needles.png",          "dense glowing teal pine needle mesh tile with tiny pure-black gaps"),
    ("default_acacia_leaves.png",         "fine red-orange glowing foliage web tile with small pure-black gaps"),
    ("default_acacia_leaves_simple.png",  "sparse red-orange foliage web tile, larger gaps"),
    ("default_aspen_leaves.png",          "pale cyan-green glowing canopy web tile with small gaps"),
    ("default_blueberry_bush_leaves.png", "green glowing bush canopy tile dotted with tiny bright blue berries, small gaps"),
    ("default_sapling.png",               "tiny oak sapling: thin amber-glowing trunk with a small neon green leaf tuft, sprite on pure black"),
    ("default_junglesapling.png",         "jungle sapling: thin trunk with magenta-green glowing leaves, sprite on pure black"),
    ("default_pine_sapling.png",          "small pine sapling: teal glowing triangular needle tiers, sprite on pure black"),
    ("default_acacia_sapling.png",        "small acacia sapling with red-orange glowing canopy, sprite on pure black"),
    ("default_aspen_sapling.png",         "slender aspen sapling with pale cyan leaves glow, sprite on pure black"),
    ("default_emergent_jungle_sapling.png","tall jungle sapling with layered magenta glow canopy, sprite on pure black"),
    ("default_bush_sapling.png",          "small bush sapling with green glow leaves, sprite on pure black"),
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
    ("default_acacia_bush_sapling.png",   "small sapling with red-orange glowing leaf puffs, sprite on pure black"),
    ("default_pine_bush_sapling.png",     "small sapling with teal glowing needle puffs, sprite on pure black"),
    ("default_blueberry_bush_sapling.png","small bush sapling with green leaves and tiny blue glow dots, sprite on pure black"),
    ("default_apple.png",                 "one round red-glowing apple with a tiny green leaf and stem, sprite on pure black"),
    ("default_blueberries.png",           "cluster of three blue-glowing berries, sprite on pure black"),
    ("default_snowball.png",              "white-blue glowing snowball sphere, sprite on pure black"),
    ("default_stick.png",                 "one diagonal thin amber-glowing stick, sprite on pure black"),
    ("default_paper.png",                 "white-glowing paper sheet rectangle, sprite on pure black"),
    ("default_book.png",                  "closed book with cyan-glowing cover edge and amber spine, sprite on pure black"),
    ("default_flint.png",                 "sharp grey flint flake with white edge glow, sprite on pure black"),
    ("default_clay_lump.png",             "small dull violet-glowing clay blob, sprite on pure black"),
    ("default_clay_brick.png",            "brick shape with red-violet glow edges, sprite on pure black"),
    ("default_coal_lump.png",             "black coal lump with white-hot glowing facets, sprite on pure black"),
    ("default_iron_lump.png",             "rough rust-orange glowing ore lump, sprite on pure black"),
    ("default_copper_lump.png",           "round orange-glowing copper lump, sprite on pure black"),
    ("default_tin_lump.png",              "silvery pale-blue glowing tin lump, sprite on pure black"),
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

# ---- B12 furnace, signs --------------------------------------------------------
sheet("B12_furnace_signs", [
    ("default_furnace_front.png", "furnace front: dark steel panel with cyan-glowing frame and a dark arched fire mouth in the lower center"),
    ("default_furnace_side.png",  "furnace side: dark steel panel with cyan hairline border"),
    ("default_furnace_top.png",   "furnace top: dark steel plate with cyan border and small vent grid"),
    ("default_furnace_bottom.png","furnace bottom: plain dark plate with faint border"),
    ("default_sign_wood.png",     "wooden sign: dark amber board with glowing edge frame, hanging sprite on pure black"),
    ("default_sign_wall_wood.png","wooden wall sign board with amber glow frame, sprite on pure black"),
    ("default_sign_steel.png",    "steel sign: dark plate with cyan glow frame, sprite on pure black"),
    ("default_sign_wall_steel.png","steel wall sign plate with cyan glow frame, sprite on pure black"),
    ("default_tool_steelaxe.png", "pixel art tool icon: axe with pale steel glowing head, dark handle with amber grip, diagonal, sprite on pure black"),
    ("default_tool_steelpick.png","pickaxe with pale steel glowing head, dark handle with amber grip, diagonal, sprite on pure black"),
    ("default_tool_steelshovel.png","shovel with pale steel glowing blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_steelsword.png","sword with pale steel glowing blade and amber guard, diagonal, sprite on pure black"),
    ("default_tool_bronzeaxe.png","axe with warm amber-bronze glowing head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_bronzepick.png","pickaxe with bronze glowing head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_bronzeshovel.png","shovel with bronze glowing blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_bronzesword.png","sword with bronze glowing blade, diagonal, sprite on pure black"),
], "tile")
for t in ["default_sign_wood.png", "default_sign_wall_wood.png", "default_sign_steel.png",
          "default_sign_wall_steel.png", "default_tool_steelaxe.png", "default_tool_steelpick.png",
          "default_tool_steelshovel.png", "default_tool_steelsword.png", "default_tool_bronzeaxe.png",
          "default_tool_bronzepick.png", "default_tool_bronzeshovel.png", "default_tool_bronzesword.png"]:
    B[t]["kind"] = "sprite"

# ---- B13 tools, mese / stone / wood ---------------------------------------------
sheet("B13_tools_1", [
    ("default_tool_meseaxe.png",     "axe with yellow-green glowing crystal head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_mesepick.png",    "pickaxe with yellow-green glowing crystal head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_meseshovel.png",  "shovel with yellow-green glowing blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_mesesword.png",   "sword with yellow-green glowing crystal blade, diagonal, sprite on pure black"),
    ("default_tool_stoneaxe.png",    "axe with rough grey stone head, faint blue glow edge, dark handle, diagonal, sprite on pure black"),
    ("default_tool_stonepick.png",   "pickaxe with rough grey stone head, faint blue glow edge, dark handle, diagonal, sprite on pure black"),
    ("default_tool_stoneshovel.png", "shovel with rough grey stone blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_stonesword.png",  "sword with rough grey stone blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_diamondaxe.png",  "axe with icy cyan-white glowing diamond head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_diamondpick.png", "pickaxe with icy cyan-white glowing diamond head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_diamondshovel.png","shovel with icy diamond glowing blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_diamondsword.png","sword with icy cyan-white glowing blade, diagonal, sprite on pure black"),
    ("default_tool_woodaxe.png",     "axe with amber-glowing wooden head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_woodpick.png",    "pickaxe with amber-glowing wooden head, dark handle, diagonal, sprite on pure black"),
    ("default_tool_woodshovel.png",  "shovel with amber-glowing wooden blade, dark handle, diagonal, sprite on pure black"),
    ("default_tool_woodsword.png",   "sword with amber-glowing wooden blade, diagonal, sprite on pure black"),
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

# ---- M01 misc 3x3 (fern frames, cracks) ------------------------------------------
sheet("M01_misc", [
    ("default_fern_2.png",        "medium fern with glowing green fronds spread wide, sprite on pure black"),
    ("default_fern_3.png",        "large lush fern with many glowing green fronds, sprite on pure black"),
    ("crack_anylength_s1.png",    "thin white-cyan glowing crack: one short branching line near the center, rest pure black, fills the square"),
    ("crack_anylength_s2.png",    "crack stage two: two branching glowing crack lines reaching toward the edges"),
    ("crack_anylength_s3.png",    "crack stage three: several branching glowing cracks crossing most of the square"),
    ("crack_anylength_s4.png",    "crack stage four: dense web of glowing cracks with small fragments"),
    ("crack_anylength_s5.png",    "crack stage five: very dense shattered web of glowing cracks across the whole square"),
    ("_spare_glow7.png",          "single small white glowing dot, sprite centered on pure black"),
    ("_spare_glow8.png",          "single small cyan glowing dot, sprite centered on pure black"),
], "sprite")
for t in ["crack_anylength_s1.png", "crack_anylength_s2.png", "crack_anylength_s3.png",
          "crack_anylength_s4.png", "crack_anylength_s5.png"]:
    B[t]["kind"] = "tilea"

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

# Variants/spares are internal, not shipped.
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
    "default_water_source_animated.png":        dict(base="default_water.png",  frames=16, style="water",  alpha_scale=0.62, variants=["water2", "water3"]),
    "default_water_flowing_animated.png":       dict(base="default_water.png",  frames=16, style="flow",   alpha_scale=0.62, variants=["water2", "water3"]),
    "default_river_water_source_animated.png":  dict(base="default_river_water.png", frames=16, style="water", alpha_scale=0.62, variants=["river2", "river3"]),
    "default_river_water_flowing_animated.png": dict(base="default_river_water.png", frames=16, style="flow",  alpha_scale=0.62, variants=["river2", "river3"]),
    "default_lava_source_animated.png":         dict(base="default_lava.png",   frames=8,  style="water", alpha_scale=1.0, speed=0.5, variants=["lava2", "lava3"]),
    "default_lava_flowing_animated.png":        dict(base="default_lava.png",   frames=16, style="flow",  alpha_scale=1.0, speed=0.5, variants=["lava2", "lava3"]),
    "default_torch_animated.png":               dict(base="default_torch_on_floor.png", frames=16, style="torch", alpha_scale=1.0, variants=["torch2", "torch3"]),
    "default_torch_on_floor_animated.png":      dict(base="default_torch_on_floor.png", frames=16, style="torch", alpha_scale=1.0, variants=["torch2", "torch3"]),
    "default_torch_on_ceiling_animated.png":    dict(base="default_torch_on_floor.png", frames=16, style="torch", alpha_scale=1.0, flip=True, variants=["torch2", "torch3"]),
    "default_furnace_front_active.png":         dict(base="default_furnace_front.png", frames=8, style="furnace", alpha_scale=1.0),
    "crack_anylength.png":                      dict(style="crackstack"),  # built from crack_anylength_s*.png
}

# ---------------------------------------------------------------- prompts --

STYLE = (
    "Retro-futuristic NEON-GRID pixel art for a cyberpunk voxel game: glowing thin wireframe "
    "and grid-line art on deep black (#06080E), Tron / synthwave vector style, like light-cycle "
    "schematics. Flat, high contrast, saturated neon accents, no realistic shading, no photo texture."
)

LATTICE = (
    "Strict pixel-art lattice: every tile is 16x16 logical pixels; each logical pixel is one solid "
    "square block of uniform color with crisp hard edges (chunky 16-bit look). Dark fills are very "
    "dark desaturated navy/graphite, never mid-grey and never noisy. Glow lines are 1 logical pixel "
    "thick and fully saturated; a dim halo pixel may sit next to a bright line. No anti-aliasing "
    "blur between logical pixels."
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
    cols = 3 if sheet_name.startswith("M01") else 4
    rows = 4 if cols == 4 else 3
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

def process():
    os.makedirs(SHEETS_DIR, exist_ok=True)
    os.makedirs(os.path.join(SHEETS_DIR, "derived"), exist_ok=True)
    stats = []
    sheets = set(c["sheet"] for c in B.values()) | set(s for s, _d in DEDICATED.values())
    missing = [s for s in sorted(sheets)
               if not os.path.exists(os.path.join(SHEETS_DIR, s + ".png"))]
    if missing:
        print("skipping (sheets not generated yet): %s" % ", ".join(missing))
    done_sheets = sheets - set(missing)
    sheet_cache = {}
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
            parts = []
            for i in range(1, 6):
                q = os.path.join(TEXDIR, "crack_anylength_s%d.png" % i)
                parts.append(Image.open(q).convert("RGBA"))
            out = vstack(parts)
            for i in range(1, 6):           # temp stage files, strip is assembled
                os.remove(os.path.join(TEXDIR, "crack_anylength_s%d.png" % i))
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
        polish()
    elif cmd == "assemble":
        assemble()
    else:
        print(__doc__)

if __name__ == "__main__":
    main()
