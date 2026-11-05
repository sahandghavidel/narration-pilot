#!/usr/bin/env python3
"""Compare fresh local window images; masks must be explicitly scoped cosmetics."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw


def compare(baseline, current, masks=None):
    if set(baseline) != set(current):
        return dict(matched=False, reason='Observed app windows differ')
    details = {}
    for app, before in baseline.items():
        a = Image.open(before).convert('RGB')
        b = Image.open(current[app]).convert('RGB')
        if a.size != b.size:
            return dict(matched=False, reason=f'{app}: image dimensions changed')
        regions = (masks or {}).get(app, [])
        if sum(r.get('rect', [0, 0, 1, 1])[2] * r.get('rect', [0, 0, 1, 1])[3] for r in regions if len(r.get('rect', [])) == 4) > .12:
            raise ValueError('Combined cosmetic masks cover too much of the window')
        for region in regions:
            rect = region.get('rect', [])
            if len(rect) != 4 or not region.get('reason'):
                raise ValueError('Every cosmetic mask needs a normalized rectangle and reason')
            x, y, w, h = rect
            if not (0 <= x < 1 and 0 <= y < 1 and 0 < w <= 1-x and 0 < h <= 1-y and w*h <= .08):
                raise ValueError('Cosmetic mask is invalid or too broad')
            box = (round(x*a.width), round(y*a.height), round((x+w)*a.width)-1, round((y+h)*a.height)-1)
            ImageDraw.Draw(a).rectangle(box, fill=(0, 0, 0))
            ImageDraw.Draw(b).rectangle(box, fill=(0, 0, 0))
        bounds = ImageChops.difference(a, b).getbbox()
        details[app] = bounds
    return dict(matched=all(v is None for v in details.values()), differences=details)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    try:
        values = json.loads(args.manifest.read_text())
        print(json.dumps(compare(values['baseline'], values['current'], values.get('masks'))))
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps(dict(matched=False, reason=str(error))))
        raise SystemExit(1)
