"""Widen only the two introductory canyon floors, without regenerating the island.

Run with Python, numpy, scipy and zstandard. The immutable v0.8 blobs are the
source; current files must be the baseline or this script's exact output, so a
second run is a no-op and unrelated local map edits are never overwritten.
"""
from copy import deepcopy
import json
from pathlib import Path
import subprocess

import numpy as np
from scipy.spatial import cKDTree
import zstandard

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "game/assets/map"
BASE_MAP = "e47785bfbad28c3f088fc0e7e3569235fcd10e9a"
BASE_HEIGHT = "039d8e9c817aeae31809b09cb7779256084666a5"
HALF_WIDTH = 64.0
OUTER = 100.0


def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


class Polyline:
    def __init__(self, routes):
        # Keep sections separate: never invent a connecting segment.
        self.a = np.concatenate([r[:-1] for r in routes])
        self.b = np.concatenate([r[1:] for r in routes])
        self.delta = (self.b - self.a)[:, [0, 2]]
        self.length2 = (self.delta ** 2).sum(axis=1)
        self.tree = cKDTree(((self.a + self.b) / 2)[:, [0, 2]])

    def project(self, points):
        _, indices = self.tree.query(points, k=min(8, len(self.a)))
        delta = self.delta[indices]
        t = np.clip(((points[:, None, :] - self.a[indices][:, :, [0, 2]])
                     * delta).sum(axis=2) / self.length2[indices], 0, 1)
        projected = self.a[indices] + t[:, :, None] * (self.b - self.a)[indices]
        d2 = ((points[:, None, :] - projected[:, :, [0, 2]]) ** 2).sum(axis=2)
        best = d2.argmin(axis=1)
        row = np.arange(len(points))
        return np.sqrt(d2[row, best]), projected[row, best]


def sample(height, points, cell, half):
    xy = (points + half) / cell
    ij = np.floor(xy).astype(int)
    ij = np.clip(ij, 0, height.shape[0] - 2)
    u, v = (xy - ij).T
    x, z = ij.T
    return (height[z, x] * (1-u) * (1-v) + height[z, x+1] * u * (1-v)
            + height[z+1, x] * (1-u) * v + height[z+1, x+1] * u * v)


def main():
    base_json = subprocess.check_output(["git", "cat-file", "blob", BASE_MAP], cwd=ROOT)
    base_zst = subprocess.check_output(["git", "cat-file", "blob", BASE_HEIGHT], cwd=ROOT)
    original = json.loads(base_json)
    result = deepcopy(original)
    cell, half, res = original["cell"], original["size"] / 2, original["res"]
    assert cell == 8.0 and res == 3073
    heights = np.frombuffer(zstandard.ZstdDecompressor().decompress(base_zst),
                            dtype="<f2").reshape(res, res).astype(np.float32) * cell
    before = heights.copy()
    routes = [np.array(s["variants"][0]["route"]) for s in original["sections"][:2]]
    assert all(s["biome"] == "sandstone" and s["variants"][0]["hw"] == 34
               for s in original["sections"][:2])
    floor = Polyline(routes)
    rim = Polyline([np.array(s["variants"][1]["route"])
                    for s in original["sections"][:2]])
    all_points = np.concatenate(routes)
    low = np.maximum(0, np.floor((all_points[:, [0, 2]].min(axis=0) - OUTER + half) / cell).astype(int))
    high = np.minimum(res-1, np.ceil((all_points[:, [0, 2]].max(axis=0) + OUTER + half) / cell).astype(int))
    gx, gz = np.meshgrid(np.arange(low[0], high[0]+1), np.arange(low[1], high[1]+1))
    points = np.column_stack((gx.ravel()*cell-half, gz.ravel()*cell-half))
    distance, projected = floor.project(points)
    rim_distance, rim_point = rim.project(points)
    old = before[gz.ravel(), gx.ravel()]
    # The original center and its interpolation cells stay exact. Only shoulders
    # are graded, with a cubic blend back to untouched rock at 100 metres.
    weight = smooth(16, 28, distance) * (1-smooth(HALF_WIDTH, OUTER, distance))
    # Upper-road support must remain intact. Existing low ground below bridge
    # decks is already an opening, so its floor can still be widened.
    support = (old > projected[:, 1] + 8) & (rim_point[:, 1] > projected[:, 1] + 8)
    weight *= np.where(support, smooth(40, 64, rim_distance), 1)
    # Keep bridge abutments intact, with a smooth margin outside each footprint.
    for bridge in original["bridges"]:
        origin = np.array(bridge["p"])[[0, 2]]
        direction = np.array([-np.sin(bridge["yaw"]), -np.cos(bridge["yaw"])])
        relative = points - origin
        along = relative @ direction
        across = np.abs(relative @ np.array([-direction[1], direction[0]]))
        for end in (0, bridge["len"]):
            clearance = np.maximum(np.abs(along-end)-16, across-bridge["width"]/2-8)
            weight *= smooth(0, 20, clearance)
    # No work extends beyond the first/last race gates into adjacent sections.
    for endpoint in (routes[0][0], routes[-1][-1]):
        weight *= smooth(24, 140, np.linalg.norm(points-endpoint[[0, 2]], axis=1))
    target = np.maximum(projected[:, 1], 0.0)
    updated = old + (target-old) * weight
    # Same near-road 12.5 cm steps and cell-unit float16 encoding as make_map.
    updated = (np.round(updated / 0.125) * 0.125 / cell).astype("<f2").astype(np.float32) * cell
    updated[weight == 0] = old[weight == 0]
    heights[gz.ravel(), gx.ravel()] = updated
    changed = heights != before
    assert np.all(distance[(updated != old)] < OUTER)
    assert np.all(heights[changed] >= 0), "Never turn dry canyon shoulders into sea"
    for route in routes:
        assert np.array_equal(sample(before, route[:, [0, 2]], cell, half),
                              sample(heights, route[:, [0, 2]], cell, half))
    for section in result["sections"][:2]:
        section["variants"][0]["hw"] = HALF_WIDTH
    # Recalculate only affected chunks, conservatively enclosing quantized data.
    chunk = original["chunk_cells"]
    count = (res-1)//chunk
    changed_chunks = 0
    for z in range(count):
        for x in range(count):
            area = (slice(z*chunk, (z+1)*chunk+1), slice(x*chunk, (x+1)*chunk+1))
            if changed[area].any():
                block = heights[area]
                result["chunks"][z*count+x] = [float(np.floor(block.min()*10)/10),
                                               float(np.ceil(block.max()*10)/10)]
                changed_chunks += 1
    # Relocate only props whose original support was cut, onto untouched shoulders.
    unmoved_json = json.dumps(result, separators=(",", ":"), ensure_ascii=False).encode()
    moved = 0
    for index, prop in enumerate(original["props"]):
        point = np.array([[prop[1], prop[3]]])
        ground_before = sample(before, point, cell, half)[0]
        ground_after = sample(heights, point, cell, half)[0]
        if abs(ground_after-ground_before) < 0.5:
            continue
        distance_to_road, projected_prop = floor.project(point)
        if distance_to_road[0] >= OUTER:
            continue
        side = point[0]-projected_prop[0, [0, 2]]
        side /= max(np.linalg.norm(side), 0.001)
        chosen = None
        for candidate_index in range(900):
            offset = 115.0 + (candidate_index % 60) * 5.0
            angle = (candidate_index // 60) * 0.21
            rotated = np.array([side[0]*np.cos(angle)-side[1]*np.sin(angle), side[0]*np.sin(angle)+side[1]*np.cos(angle)])
            candidate = projected_prop[0, [0, 2]] + rotated*offset
            candidate = candidate[None, :]
            separation, _ = floor.project(candidate)
            rim_separation, _ = rim.project(candidate)
            h = sample(heights, candidate, cell, half)[0]
            if separation[0] < 105 or rim_separation[0] < 50 or h < 1.5:
                continue
            if abs(h-sample(before, candidate, cell, half)[0]) > 0.01:
                continue
            chosen = candidate[0], h
            break
        assert chosen is not None, (index, prop[0], "no safe shoulder")
        updated_prop = result["props"][index]
        updated_prop[1], updated_prop[3] = map(float, chosen[0])
        updated_prop[2] = float(chosen[1] + prop[2] - ground_before)
        moved += 1
    assert len(result["props"]) == len(original["props"])
    assert result["checkpoints"] == original["checkpoints"]
    assert result["sections"][2:] == original["sections"][2:]
    for k in original.keys()-{"sections", "chunks", "props"}:
        assert result[k] == original[k], k
    output_json = json.dumps(result, separators=(",", ":"), ensure_ascii=False).encode()
    output_zst = zstandard.ZstdCompressor(level=19, threads=0).compress((heights/cell).astype("<f2").tobytes())
    for name, baseline, output in (("map.json", base_json, output_json), ("height.zst", base_zst, output_zst)):
        if (ASSETS/name).read_bytes() not in (baseline, output, unmoved_json if name == "map.json" else output):
            raise SystemExit(f"Refusing to overwrite unrelated edits in {name}")
    for name, output in (("map.json", output_json), ("height.zst", output_zst)):
        if (ASSETS/name).read_bytes() != output:
            (ASSETS/name).write_bytes(output)
    delta = heights-before
    print(json.dumps({"changed_cells": int(changed.sum()), "affected_chunks": changed_chunks,
                      "max_cut_m": float(-delta.min()), "max_fill_m": float(delta.max()),
                      "route_center_change_m": 0, "half_width_m": HALF_WIDTH,
                      "outer_blend_m": OUTER, "props_repositioned": moved}))


if __name__ == "__main__":
    main()
