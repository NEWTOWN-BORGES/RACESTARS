"""Check the four regenerated trees without Blender or third-party packages.

python tools/vegetation_check.py
python tools/vegetation_check.py --compare-ref HEAD

The optional comparison reads original GLBs from Git without changing the checkout.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
# Original triangle counts and heights preserve the mobile and collision budgets.
BASELINE = {
    "tree_acacia": (196, 8.3707),
    "tree_acacia_b": (196, 6.6811),
    "tree_giant": (1088, 47.2651),
    "pine": (152, 15.6685),
}


def inspect_glb(data):
    assert data[:4] == b"glTF" and struct.unpack_from("<I", data, 4)[0] == 2
    assert struct.unpack_from("<I", data, 8)[0] == len(data), "truncated GLB"
    json_length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    document = json.loads(data[20:20 + json_length])
    binary_offset = 28 + json_length
    vertices, triangles = [], 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            assert primitive.get("mode", 4) == 4, "expected triangles"
            assert "COLOR_0" in primitive["attributes"], "lost foliage vertex colors"
            position = document["accessors"][primitive["attributes"]["POSITION"]]
            assert position["componentType"] == 5126 and position["type"] == "VEC3"
            view = document["bufferViews"][position["bufferView"]]
            offset = binary_offset + view.get("byteOffset", 0) + position.get("byteOffset", 0)
            stride = view.get("byteStride", 12)
            points = [struct.unpack_from("<3f", data, offset + n * stride)
                      for n in range(position["count"])]
            assert all(math.isfinite(value) for p in points for value in p)
            for axis in range(3):
                assert abs(min(p[axis] for p in points) - position["min"][axis]) < 0.001
                assert abs(max(p[axis] for p in points) - position["max"][axis]) < 0.001
            vertices.extend(points)
            indices = document["accessors"][primitive["indices"]]
            assert indices["count"] % 3 == 0
            triangles += indices["count"] // 3
    low = [min(p[axis] for p in vertices) for axis in range(3)]
    high = [max(p[axis] for p in vertices) for axis in range(3)]
    return triangles, low, high


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare-ref", help="compare against a Git revision, e.g. HEAD")
    args = parser.parse_args()
    for name, (baseline_triangles, baseline_height) in BASELINE.items():
        path = "game/assets/models/" + name + ".glb"
        triangles, low, high = inspect_glb((ROOT / path).read_bytes())
        assert triangles <= baseline_triangles * 1.5, (name, "triangle budget")
        assert abs(high[1] - baseline_height) < baseline_height * 0.15, (name, "height budget")
        assert -0.3 < low[1] <= 0.01, (name, "root moved away from ground")
        if args.compare_ref:
            original = subprocess.check_output(["git", "show", args.compare_ref + ":" + path], cwd=ROOT)
            old_triangles, old_low, old_high = inspect_glb(original)
            assert triangles <= old_triangles * 1.5, (name, "triangle regression")
            assert abs(low[1] - old_low[1]) < 0.2, (name, "trunk base changed")
            for axis in (0, 2):
                assert high[axis] - low[axis] <= (old_high[axis] - old_low[axis]) * 1.2
        print(f"{name}: {triangles} triangles, {high[1]:.2f} m; bounds/colors OK")
    print("PASS: all four trees remain within mobile geometry and silhouette budgets")


if __name__ == "__main__":
    main()
