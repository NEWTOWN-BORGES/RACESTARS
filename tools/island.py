"""Deterministic coastline applied after roads, tunnels and mountain shaping.

The ocean mask is independent of terrain height: an underground road or ravine
inside the island is not ocean just because its floor is below sea level.
"""
import numpy as np
from scipy.ndimage import zoom


def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def coastline(x, z, path_distance, centers, half_size):
    """Positive inland distance; preserve race corridors and all region centers.

    Route distance is measured on a 32 m grid. A 900 m headland around each
    route leaves at least 450 m of unchanged terrain before the coastal blend.
    The final border constraint keeps all four edges below the sea, including
    the starting peninsula which approaches within 672 m of the heightmap edge.
    """
    angle = np.arctan2(z, x)
    radius = (9850.0 + 760.0 * np.sin(3.0 * angle + 0.45)
              + 510.0 * np.sin(5.0 * angle - 1.1)
              + 290.0 * np.sin(9.0 * angle + 2.0))
    # Small coves between the larger peninsulas, without a regular radial rim.
    ripple = 100.0 * np.sin(x / 470.0 + np.sin(z / 730.0)) * np.sin(z / 390.0)
    distance = radius - np.hypot(x, z) + ripple
    roads = zoom(path_distance.astype(np.float32), x.shape[0] / path_distance.shape[0], order=1)
    distance = np.maximum(distance, 900.0 - roads)
    for cx, cz in centers:
        distance = np.maximum(distance, 1200.0 - np.hypot(x - cx, z - cz))
    distance = np.minimum(distance, half_size - np.maximum(np.abs(x), np.abs(z)) - 160.0)
    return distance.astype(np.float32)


def shape_coast(heights, coast_distance, sea_level=0.0):
    """Keep inland relief exact; grade shores to sand shelves and a deep seabed."""
    shore = sea_level + np.maximum(-72.0, coast_distance * 0.065)
    weight = smooth(0.0, 450.0, coast_distance)
    return (shore * (1.0 - weight) + heights * weight).astype(np.float32)


def ocean_rectangles(coast_distance, map_size, ocean_size, cell=128.0):
    """Merge water grid runs into static collision boxes, including open sea.

    A coastal cell counts as water if any of its terrain samples touch ocean.
    Its slight extension under dry beaches prevents gaps at the shoreline;
    preserved underground race corridors are at least 450 m farther inland.
    """
    samples = coast_distance.shape[0] - 1
    count = int(round(map_size / cell))
    stride = samples // count
    assert count * stride == samples
    wet = coast_distance[:-1, :-1].reshape(count, stride, count, stride).min(axis=(1, 3)) <= 0.0
    rectangles, active = [], {}
    half = map_size / 2.0
    for row in range(count + 1):
        runs = []
        if row < count:
            bounds = np.flatnonzero(np.diff(np.r_[False, wet[row], False].astype(np.int8)))
            runs = list(zip(bounds[::2], bounds[1::2]))
        current = set(runs)
        for run in list(active):
            if run not in current:
                start = active.pop(run)
                left, right = run
                rectangles.append([float(-half + (left + right) * cell / 2),
                                   float(-half + (start + row) * cell / 2),
                                   float((right - left) * cell), float((row - start) * cell)])
        for run in runs:
            active.setdefault(run, row)
    extension = (ocean_size - map_size) / 2.0
    for side in (-1.0, 1.0):
        center = side * (half + extension / 2)
        rectangles.append([center, 0.0, extension, ocean_size])
        rectangles.append([0.0, center, map_size, extension])
    return rectangles
