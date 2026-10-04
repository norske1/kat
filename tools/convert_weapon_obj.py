"""Converts a Blender-exported weapon OBJ into a Roblox-ready OBJ.

- rotates it so the barrel points along -Z (Roblox forward) with +Y up
- scales it so the grip-to-muzzle distance matches the gameplay model, with the grip at the origin
- merges every object into one mesh per material (Gunmetal, Polymer, ...) so Studio imports a few
  MeshParts instead of hundreds, and triangulates n-gons
- prints the grip / muzzle positions as fractions of the bounding box for Weapons/Config.luau

usage: python tools/convert_weapon_obj.py in.obj in.mtl out.obj --grip X Y Z --muzzle X Y Z --reach STUDS
(--grip / --muzzle are in the source file's coordinates; the muzzle must be on the +X side)
"""

import argparse
import re
from collections import defaultdict

MAX_TRIS = 19000  # Roblox limit is 20k triangles per mesh


def rotate(v):
    # 90 degrees about +Y: source +X (muzzle) -> -Z
    x, y, z = v
    return (z, y, -x)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def triangulate(points):
    """Ear clipping on the polygon projected onto its best-fit plane. Returns index triples."""
    n = len(points)
    if n == 3:
        return [(0, 1, 2)]
    normal = [0.0, 0.0, 0.0]
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        normal[0] += (a[1] - b[1]) * (a[2] + b[2])
        normal[1] += (a[2] - b[2]) * (a[0] + b[0])
        normal[2] += (a[0] - b[0]) * (a[1] + b[1])
    axis = max(range(3), key=lambda k: abs(normal[k]))
    keep = [k for k in range(3) if k != axis]
    flat = [(p[keep[0]], p[keep[1]]) for p in points]
    if normal[axis] < 0:
        flat = [(x, -y) for x, y in flat]

    def area2(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    def inside(p, a, b, c):
        return area2(a, b, p) >= 0 and area2(b, c, p) >= 0 and area2(c, a, p) >= 0

    idx = list(range(n))
    tris = []
    guard = 0
    while len(idx) > 3 and guard < n * n:
        guard += 1
        clipped = False
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = flat[i0], flat[i1], flat[i2]
            if area2(a, b, c) <= 1e-12:
                continue
            if any(inside(flat[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            clipped = True
            break
        if not clipped:
            break
    if len(idx) > 3 or not clipped and len(idx) == 3 and not tris:
        pass
    if len(idx) >= 3:  # degenerate leftovers: fan them
        for k in range(1, len(idx) - 1):
            tris.append((idx[0], idx[k], idx[k + 1]))
    return tris


def material_name(raw):
    name = raw.split("|")[-1].strip("_ ").replace("_Details", "").replace("_", "")
    return re.sub(r"[^A-Za-z0-9]", "", name) or "Body"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("obj")
    ap.add_argument("mtl")
    ap.add_argument("out")
    ap.add_argument("--grip", type=float, nargs=3, required=True)
    ap.add_argument("--muzzle", type=float, nargs=3, required=True)
    ap.add_argument("--reach", type=float, required=True, help="grip-to-muzzle distance in studs")
    args = ap.parse_args()

    scale = args.reach / (args.muzzle[0] - args.grip[0])
    grip = rotate(args.grip)

    def place(v):
        r = rotate(v)
        return tuple((r[k] - grip[k]) * scale for k in range(3))

    vs, vts, vns = [], [], []
    faces = defaultdict(list)  # material -> list of [(v, vt, vn)]
    mat = "Body"
    for line in open(args.obj):
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            vs.append(place(tuple(map(float, parts[1:4]))))
        elif parts[0] == "vt":
            vts.append(tuple(map(float, parts[1:3])))
        elif parts[0] == "vn":
            vns.append(rotate(tuple(map(float, parts[1:4]))))
        elif parts[0] == "usemtl":
            mat = material_name(line.split(None, 1)[1].strip())
        elif parts[0] == "f":
            corners = []
            for c in parts[1:]:
                bits = c.split("/")
                vi = int(bits[0])
                ti = int(bits[1]) if len(bits) > 1 and bits[1] else 0
                ni = int(bits[2]) if len(bits) > 2 and bits[2] else 0
                corners.append((vi, ti, ni))
            pts = [vs[c[0] - 1] for c in corners]
            for a, b, c in triangulate(pts):
                faces[mat].append((corners[a], corners[b], corners[c]))

    lo = [min(v[k] for v in vs) for k in range(3)]
    hi = [max(v[k] for v in vs) for k in range(3)]
    center = [(lo[k] + hi[k]) / 2 for k in range(3)]
    half = [(hi[k] - lo[k]) / 2 for k in range(3)]
    muzzle = place(tuple(args.muzzle))

    def frac(p):
        return tuple(round((p[k] - center[k]) / half[k], 4) for k in range(3))

    with open(args.out, "w") as out:
        mtl_name = args.out.rsplit("/", 1)[-1].rsplit(".", 1)[0] + ".mtl"
        out.write(f"# Roblox-ready weapon mesh (barrel -Z, grip at origin, studs)\nmtllib {mtl_name}\n")
        for v in vs:
            out.write("v %.5f %.5f %.5f\n" % v)
        for t in vts:
            out.write("vt %.5f %.5f\n" % t)
        for n in vns:
            out.write("vn %.5f %.5f %.5f\n" % n)
        for m, tris in sorted(faces.items()):
            for chunk in range(0, len(tris), MAX_TRIS):
                part = tris[chunk : chunk + MAX_TRIS]
                name = m if chunk == 0 else f"{m}{chunk // MAX_TRIS + 1}"
                out.write(f"o {name}\nusemtl {m}\n")
                for tri in part:
                    out.write("f " + " ".join("%d/%s/%s" % (v, t or "", n or "") for v, t, n in tri) + "\n")
            print(f"  {m}: {len(tris)} triangles")

    # rewrite the material library with the merged names
    colors = {}
    cur = None
    for line in open(args.mtl):
        p = line.split()
        if p and p[0] == "newmtl":
            cur = material_name(line.split(None, 1)[1].strip())
        elif p and p[0] == "Kd" and cur:
            colors[cur] = p[1:4]
    with open(args.out.rsplit(".", 1)[0] + ".mtl", "w") as out:
        for m, kd in colors.items():
            out.write(f"newmtl {m}\nKd {' '.join(kd)}\nKa 0 0 0\nKs 0.5 0.5 0.5\nNs 300\nd 1\nillum 2\n\n")

    print("  size (studs):", tuple(round(2 * h, 3) for h in half))
    print("  grip fraction:", frac((0, 0, 0)))
    print("  muzzle fraction:", frac(muzzle))
    print("  length (Z):", round(2 * half[2], 3))


if __name__ == "__main__":
    main()
