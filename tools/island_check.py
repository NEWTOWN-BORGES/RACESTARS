"""Check generated island data, route compatibility and sea collision coverage.

Run after make_map.py: python tools/island_check.py [--baseline-ref 0bd6885]
The optional baseline comparison reads Git objects without changing the checkout.
"""
import argparse
import json
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image
from scipy.ndimage import label
import zstandard


def check(baseline_ref=None):
    root = Path(__file__).resolve().parents[1]
    assets = root / 'game/assets/map'
    data = json.loads((assets / 'map.json').read_text())
    size, res, cell = data['size'], data['res'], data['cell']
    sea = data['ocean']['y']
    heights = np.frombuffer(zstandard.ZstdDecompressor().decompress((assets / 'height.zst').read_bytes()),
                            dtype=np.float16).astype(np.float32).reshape(res, res) * cell
    mask = np.asarray(Image.open(assets / 'ocean_mask.png').convert('L'))

    def sample_mask(points):
        pixel = np.clip(((points + size / 2) / size * mask.shape[0]).astype(int), 0, mask.shape[0] - 1)
        return mask[pixel[:, 1], pixel[:, 0]]

    borders = np.concatenate([heights[0], heights[-1], heights[:, 0], heights[:, -1]])
    assert np.all(borders < sea), 'O perímetro do terreno tem terra à vista'
    assert np.all(np.concatenate([mask[0], mask[-1], mask[:, 0], mask[:, -1]]) == 255)
    assert len(data['zones']) == 16 and len(data['events']) == 3
    assert np.all(sample_mask(np.array([zone['c'] for zone in data['zones']])) == 0)
    labels, count = label(mask < 128)
    components = np.bincount(labels.ravel())[1:]
    assert count == 1, f'A ilha separou-se em {count} pedaços'

    routes = [variant['route'] for section in data['sections'] for variant in section['variants']]
    routes += [event['route'] for event in data['events']]
    route_points = np.vstack(routes)
    coords = route_points[:, [0, 2]]
    assert np.all(sample_mask(coords) == 0), 'O oceano invade uma pista'
    rects = np.asarray(data['ocean']['collision_rects'])
    for cx, cz, sx, sz in rects:
        on_route = (np.abs(coords[:, 0] - cx) <= sx / 2) & (np.abs(coords[:, 1] - cz) <= sz / 2)
        assert not np.any(on_route), 'Uma colisão de oceano invade uma pista/túnel'
    # Every mask texel clearly in the sea must have supporting water collision.
    zz, xx = np.nonzero(mask[::8, ::8] > 240)
    ocean_points = np.stack([xx * 8 + 0.5, zz * 8 + 0.5], 1) / mask.shape[0] * size - size / 2
    covered = np.zeros(len(ocean_points), bool)
    for cx, cz, sx, sz in rects:
        covered |= (np.abs(ocean_points[:, 0] - cx) <= sx / 2) & (np.abs(ocean_points[:, 1] - cz) <= sz / 2)
    assert np.all(covered), f'{np.count_nonzero(~covered)} amostras do mar sem colisão'

    words = np.frombuffer(zstandard.ZstdDecompressor().decompress((assets / 'veg.zst').read_bytes()), dtype='<u4').reshape(-1, 2)
    xy = np.stack([words[:, 0] & 65535, words[:, 0] >> 16], 1).astype(float) / 2 - size / 2
    plant_y = (words[:, 1] & 65535).astype(float) / 64 - 100
    assert len(words) == data['veg_count']
    assert np.all(plant_y > sea) and np.all(sample_mask(xy) < 128), 'Vegetação submersa'
    for collection in ('grass', 'flowers', 'ferns', 'herds'):
        items = data[collection]
        positions = np.array([item[1:4] if collection == 'herds' else item[:3] for item in items])
        assert np.all(positions[:, 1] > sea), f'{collection} submersos'

    if baseline_ref:
        raw = subprocess.check_output(['git', 'show', f'{baseline_ref}:game/assets/map/map.json'], cwd=root)
        original = json.loads(raw)
        original_routes = [v['route'] for s in original['sections'] for v in s['variants']]
        original_routes += [event['route'] for event in original['events']]
        assert len(routes) == len(original_routes)
        max_height_error = 0.0
        for current, previous in zip(routes, original_routes):
            current, previous = np.asarray(current), np.asarray(previous)
            np.testing.assert_array_equal(current[:, [0, 2]], previous[:, [0, 2]], err_msg='O traçado de uma rota mudou')
            # JSON rounds heights to centimeters; floating-point library versions
            # can tip one rounded sample. Terrain itself is quantized to 12.5 cm.
            np.testing.assert_allclose(current[:, 1], previous[:, 1], atol=0.01001, rtol=0,
                                       err_msg='A altura de uma rota mudou face à versão base')
            max_height_error = max(max_height_error, float(np.max(np.abs(current[:, 1] - previous[:, 1]))))

        def same_structure(current, previous):
            if isinstance(current, dict):
                return current.keys() == previous.keys() and all(same_structure(current[key], previous[key]) for key in current)
            if isinstance(current, list):
                return len(current) == len(previous) and all(same_structure(a, b) for a, b in zip(current, previous))
            if isinstance(current, (float, int)):
                return abs(current - previous) < 1e-5
            return current == previous

        for key in ('start', 'finish', 'checkpoints', 'tunnels', 'bridges', 'aqueducts', 'waters', 'roofs'):
            assert same_structure(data[key], original[key]), f'{key} mudou face à versão base'
        print(f'Base {baseline_ref}: {len(routes)} traçados idênticos (erro de altura máx. {max_height_error:.2f} m); '
              'portões, túneis e pontes preservados.')
    print(f'Ilha ligada: {int(components.max()):,} pixels de terra; mar {100 * np.mean(mask >= 128):.1f}%.')
    print(f'Perímetro: altura máxima {borders.max():.2f} m; {len(rects)} colisões cobrem {len(ocean_points)} amostras do mar.')
    print(f'{len(route_points):,} pontos de rotas secos; {len(words):,} plantas fora de água; 16 regiões e 3 provas preservadas.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref')
    check(parser.parse_args().baseline_ref)
