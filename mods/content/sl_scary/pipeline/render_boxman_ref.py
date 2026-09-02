#!/usr/bin/env python3
"""Software render of SimpleOutlinedBoxman.glb for the mob style ref.

Faithful parts: mesh geometry, node hierarchy, object animation sampled
at its first key pose, per-face colors sampled from the game's real 2x2
material texture (sl_boxman_neon.png) through each face's UV. Then the
game look is added: pure-black body parts, neon rim light (cyan), soft
white emissive core - the wire-glow look of the menu art.
"""
import json, struct, math, sys, subprocess, collections

GLB = "mods/content/sl_characters/models/SimpleOutlinedBoxman.glb"
TEX = "mods/content/sl_characters/textures/sl_boxman_neon.png"
OUT = "/tmp/boxman_render.png"
SIZE = 1024
FOV = 0.55  # half-fov rad
PITCH, YAW = 0.10, 0.55

sys.path.insert(0, "mods/content/sl_scary/pipeline")
from transpose_sprite_strip import read_png


def load(path):
    b = open(path, "rb").read()
    off = 12
    jb = None
    bb = b""
    while off + 8 <= len(b):
        clen, ct = struct.unpack("<II", b[off:off + 8]); off += 8
        if ct == 0x4E4F534A: jb = b[off:off + clen]
        else: bb = b[off:off + clen]
        off += clen
    return json.loads(jb.decode("utf8")), bb


def acc_data(g, bb, ai):
    bv = g["bufferViews"][ai["bufferView"]]
    o = bv.get("byteOffset", 0)
    ct = ai["componentType"]
    code = {5126: "f", 5123: "H", 5121: "B", 5125: "I", 5120: "b", 5122: "h"}.get(ct)
    if code is None:
        raise KeyError("componentType %s unsupported (acc %s)" % (ct, ai))
    sz = {5126: 4, 5123: 2, 5121: 1, 5125: 4, 5120: 1, 5122: 2}[ct]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[ai["type"]]
    stride = bv.get("byteStride", comps * sz)
    out = []
    for i in range(ai["count"]):
        oo = o + i * stride
        out.append(struct.unpack("<%d%s" % (comps, code), bb[oo:oo + comps * sz]))
    return out


def quat_mul(q, r):
    a, b, c, d = q; e, f, g, h = r
    return (a * e - b * f - c * g - d * h,
            a * f + b * e + c * h - d * g,
            a * g - b * h + c * e + d * f,
            a * h + b * g - c * f + d * e)


def quat_norm(q):
    L = math.sqrt(sum(v * v for v in q)) or 1.0
    return tuple(v / L for v in q)


def quat_slerp(q0, q1, t):
    q0 = quat_norm(q0); q1 = quat_norm(q1)
    dot = sum(a * b for a, b in zip(q0, q1))
    if dot < 0:
        q1 = tuple(-v for v in q1); dot = -dot
    if dot > 0.9995:
        return quat_norm(tuple(a + t * (b - a) for a, b in zip(q0, q1)))
    th = math.acos(max(-1, min(1, dot)))
    s0 = math.sin((1 - t) * th) / math.sin(th)
    s1 = math.sin(t * th) / math.sin(th)
    return quat_norm(tuple(a * s0 + b * s1 for a, b in zip(q0, q1)))


def mix(v0, v1, t):
    return tuple(a + t * (b - a) for a, b in zip(v0, v1))


def mat_of(t, r, s):
    x, y, z, w = r
    tx, ty, tz = t
    sx, sy, sz = s
    return [[sx * (1 - 2 * (y * y + z * z)), 2 * sx * (x * y - w * z), 2 * sx * (x * z + w * y), tx],
            [2 * sy * (x * y + w * z), sy * (1 - 2 * (x * x + z * z)), 2 * sy * (y * z - w * x), ty],
            [2 * sz * (x * z - w * y), 2 * sz * (y * z + w * x), sz * (1 - 2 * (x * x + y * y)), tz],
            [0, 0, 0, 1]]


def mmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def mv(m, v):
    x, y, z = v
    return (m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
            m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
            m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3])


def norm3(v):
    L = math.sqrt(sum(a * a for a in v)) or 1.0
    return tuple(a / L for a in v)


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def main():
    g, bb = load(GLB)
    # game material texture (2x2)
    w, h, ct, _, _, trows = read_png(TEX)
    tch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    tex = {}
    for yy, r in enumerate(trows):
        for xx in range(w):
            q = r[xx * tch:(xx + 1) * tch]
            if ct == 6: c = (q[0], q[1], q[2])
            elif ct == 2: c = (q[0], q[1], q[2])
            else: c = (q[0], q[0], q[0])
            tex[(xx, yy)] = c
    def sample(uv):
        u, v = uv
        tx = max(0, min(w - 1, int(u * w)))
        ty = max(0, min(h - 1, int((1.0 - v) * h)))
        return tex[(tx, ty)]

    # Art direction for the style reference: the 2x2 material texture and
    # the menu art palette (near-black bg; hot cyan, magenta, white).
    # UV-center sampling of a 2x2 texture only lands on red/white texels
    # (see part digest), so parts get one accent each from the game
    # palette - what the neon wire-glow boxman reads as at distance.
    # Body panels render dark (the model's base colour is black); the
    # neon shows as rims/emissive, exactly like the wire-glow theme.
    ACCENTS = {"Head": (0, 232, 255), "Chest": (255, 255, 255),
               "Belly": (232, 0, 168), "Hips": (0, 168, 232),
               "Hand L": (232, 0, 168), "Hand R": (232, 0, 168),
               "Leg L": (0, 168, 232), "Leg R": (0, 168, 232)}

    def part_col(name):
        c = ACCENTS.get(name, (200, 200, 200))
        # dark tinted panel: colour hint at ~18%, never pure black so the
        # separate neon rim and emissive ring carry the wire-glow look
        return (int(c[0] * 0.18 + 8), int(c[1] * 0.18 + 10),
                int(c[2] * 0.18 + 14))

    nodes = g["nodes"]
    children = {i: n.get("children", []) for i, n in enumerate(nodes)}
    # ---- animation pose at first keyframe time
    pose = {}
    try:
        for a in g.get("animations", []):
            for ch in a["channels"]:
                tgt = ch["target"]
                node = tgt.get("node")
                path = tgt.get("path")
                sp = a["samplers"][ch["sampler"]]
                times = acc_data(g, bb, g["accessors"][sp["input"]])
                vals = acc_data(g, bb, g["accessors"][sp["output"]])
                t = times[0][0]
                if path in ("translation", "scale"):
                    pose.setdefault(node, {})[path] = vals[0]
                elif path == "rotation":
                    pose.setdefault(node, {})[path] = vals[0]
    except Exception as e:
        print("anim pose fallback to bind (", e, ")")
    for ni, nd in enumerate(nodes):
        p = pose.get(ni, {})
        nd_t = tuple(p.get("translation", nd.get("translation") or (0, 0, 0)))
        nd_r = quat_norm(tuple(p.get("rotation", nd.get("rotation") or (0, 0, 0, 1))))
        nd_s = tuple(p.get("scale", nd.get("scale") or (1, 1, 1)))
        nodes[ni] = dict(nd, _t=nd_t, _r=nd_r, _s=nd_s)
    worldm = {}

    def walk(ni, pm):
        nd = nodes[ni]
        m = mat_of(nd["_t"], nd["_r"], nd["_s"])
        wm = mmul(pm, m)
        worldm[ni] = wm
        for c in children.get(ni, []):
            walk(c, wm)
    scene = g["scenes"][0]
    ids = scene.get("nodes", list(range(len(nodes))))
    I4 = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    for r in ids:
        walk(r, I4)

    # mesh -> node name map
    node_of_mesh = {}
    for nd, wm in worldm.items():
        if "mesh" in nodes[nd]:
            node_of_mesh[nodes[nd]["mesh"]] = nodes[nd].get("name", "part%d" % nd)

    # assemble triangles
    tris = []
    for mi, mesh in enumerate(g["meshes"]):
        name = node_of_mesh.get(mi, "part%d" % mi)
        wm = worldm[[nd for nd in worldm if nodes[nd].get("mesh") == mi][0]]
        for prim in mesh["primitives"]:
            att = prim["attributes"]
            pos = acc_data(g, bb, g["accessors"][att["POSITION"]])
            uvs = acc_data(g, bb, g["accessors"][att["TEXCOORD_0"]]) if "TEXCOORD_0" in att else None
            idx = acc_data(g, bb, g["accessors"][prim["indices"]]) if prim.get("indices") is not None else None
            n0 = len(pos)
            count = n0 if idx is None else len(idx)
            for i in range(0, count - (count % 3), 3):
                ii = [i, i + 1, i + 2] if idx is None else [idx[i][0], idx[i + 1][0], idx[i + 2][0]]
                pts = [mv(wm, pos[j][0:3]) for j in ii]
                cuv = None
                if uvs:
                    cuv = tuple(sum(uvs[j][k] for j in ii) / 3 for k in range(2))
                tris.append((name, pts, cuv))
    allpts = [p for _, pts, _ in tris for p in pts]
    xs = [p[0] for p in allpts]; ys = [p[1] for p in allpts]; zs = [p[2] for p in allpts]
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    hspan = max(max(xs) - min(xs), max(ys) - min(ys))
    # camera
    cp, sp_ = math.cos(PITCH), math.sin(PITCH)
    cy_, sy_ = math.cos(YAW), math.sin(YAW)
    dist = CAM_SPAN = 3.1 * hspan
    eye = (cx + dist * sy_ * cp, cy + dist * sp_, 0 + dist * cy_ * cp)
    fwd = norm3(sub((cx, cy, 0), eye))
    right = norm3((fwd[2], 0, -fwd[0]))
    up = norm3((right[1] * fwd[2] - right[2] * fwd[1],
                right[2] * fwd[0] - right[0] * fwd[2],
                right[0] * fwd[1] - right[1] * fwd[0]))
    focal = (SIZE / 2) / math.tan(FOV)
    img = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    zbuf = [[1e18] * SIZE for _ in range(SIZE)]

    def proj(p):
        d = sub(p, eye)
        dz = d[0] * fwd[0] + d[1] * fwd[1] + d[2] * fwd[2]
        if dz <= 0.05: return None
        dx = d[0] * right[0] + d[1] * right[1] + d[2] * right[2]
        dy = d[0] * up[0] + d[1] * up[1] + d[2] * up[2]
        return (SIZE / 2 + dx / dz * focal, SIZE / 2 - dy / dz * focal, dz)

    def fill(p1, p2, p3, col):
        x0 = int(max(0, min(p1[0], p2[0], p3[0]))); x1 = int(min(SIZE - 1, max(p1[0], p2[0], p3[0])))
        y0 = int(max(0, min(p1[1], p2[1], p3[1]))); y1 = int(min(SIZE - 1, max(p1[1], p2[1], p3[1])))
        area = (p2[0] - p1[0]) * (p3[1] - p1[1]) - (p3[0] - p1[0]) * (p2[1] - p1[1])
        if abs(area) < 1e-9: return
        for yy in range(y0, y1 + 1):
            row = img[yy]; zr = zbuf[yy]
            for xx in range(x0, x1 + 1):
                px, py = xx + 0.5, yy + 0.5
                w0 = ((p2[0] - px) * (p3[1] - py) - (p3[0] - px) * (p2[1] - py)) / area
                w1 = ((p3[0] - px) * (p1[1] - py) - (p1[0] - px) * (p3[1] - py)) / area
                w2 = 1 - w0 - w1
                if w0 >= 0 and w1 >= 0 and w2 >= 0:
                    z = p1[2] * w0 + p2[2] * w1 + p3[2] * w2
                    if z < zr[xx]:
                        zr[xx] = z; row[xx] = col
    # digest of part colors
    digest = collections.Counter()
    drawn = []
    for name, pts, cuv in tris:
        col = part_col(name)
        digest[(name, "#%02X%02X%02X" % col)] += 1
        pr = [proj(p) for p in pts]
        if any(pp is None for pp in pr): continue
        drawn.append((sum(pp[2] for pp in pr) / 3, pr, col))
    for (name, colhex), n in sorted(digest.items(), key=lambda kv: -kv[1]):
        print("part", name, colhex, n)
    drawn.sort(key=lambda d: -d[0])
    for _, pr, col in drawn:
        fill(pr[0], pr[1], pr[2], (col[0], col[1], col[2], 255))
    # write base
    raw = bytearray()
    for yy in range(SIZE):
        for xx in range(SIZE):
            raw += bytes(img[yy][xx])
    open("/tmp/bm_base.rgba", "wb").write(bytes(raw))
    subprocess.run(["convert", "-size", "%dx%d" % (SIZE, SIZE), "-depth", "8",
                    "rgba:/tmp/bm_base.rgba",
                    "-background", "#000008", "-alpha", "background", "PNG32:/tmp/bm_flat.png"], check=True)
    # rim glow: cyan halo ring = dilated silhouette minus silhouette,
    # placed behind the body; white inner rim for the emissive core.
    subprocess.run(["convert", "/tmp/bm_flat.png", "-alpha", "extract",
                    "-morphology", "Dilate", "Disk:22", "PNG32:/tmp/bm_halo.png"], check=True)
    subprocess.run(["convert", "/tmp/bm_halo.png", "(", "/tmp/bm_flat.png", "-alpha", "extract", ")",
                    "-compose", "Difference", "-composite", "-transparent", "black",
                    "-fill", "#00E8FF", "-fuzz", "5%", "-opaque", "#FFFFFF",
                    "PNG32:/tmp/bm_ring.png"], check=True)
    subprocess.run(["convert", "/tmp/bm_flat.png", "-alpha", "extract",
                    "-morphology", "Dilate", "Disk:6", "PNG32:/tmp/bm_halo2.png"], check=True)
    subprocess.run(["convert", "/tmp/bm_halo2.png", "(", "/tmp/bm_flat.png", "-alpha", "extract", ")",
                    "-compose", "Difference", "-composite", "-transparent", "black",
                    "-fill", "#FFFFFF", "-fuzz", "5%", "-opaque", "#FFFFFF",
                    "-alpha", "set", "-channel", "A", "-evaluate", "multiply", "0.55",
                    "PNG32:/tmp/bm_rim.png"], check=True)
    subprocess.run(["convert", "/tmp/bm_ring.png", "/tmp/bm_rim.png", "-composite",
                    "/tmp/bm_flat.png", "-composite", "-quality", "95", "PNG32:" + OUT], check=True)
    print("wrote", OUT)


main()
