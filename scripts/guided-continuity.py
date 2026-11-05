#!/usr/bin/env python3
"""Compare fresh local window images; masks must be explicitly scoped cosmetics."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw


def caret_blink(delta, view):
    """The runner separately checks that AX content, focus and geometry match."""
    window = view.get('window', {})
    if not window.get('w') or not window.get('h'):
        return False
    sx, sy = delta.width / window['w'], delta.height / window['h']
    box = delta.getbbox()
    if not box or box[2]-box[0] > 18 or box[3]-box[1] > 60*sy:
        return False
    # Ignore JPEG ringing solely to identify the shape of this one difference.
    ink = delta.crop(box).convert('L').point(lambda v: 255 if v > 64 else 0)
    line = ink.getbbox()
    if not line:
        return False
    w, h = line[2]-line[0], line[3]-line[1]
    if w > max(2, 2*sx) or not 8*sy <= h <= 50*sy or ink.histogram()[255] < .9*w*h:
        return False
    x = window['x'] + (box[0]+line[0])/sx
    y = window['y'] + (box[1]+line[1])/sy
    for field in view.get('elements', []):
        if field.get('focused') and field['role'] in ('combobox', 'textfield', 'textarea'):
            r = field['rect']
            if r['x']-1 <= x and x+w/sx <= r['x']+r['width']+1 and r['y']-1 <= y and y+h/sy <= r['y']+r['height']+1:
                return True
    return False


def compare(baseline, current, masks=None, views=None):
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
        delta = ImageChops.difference(a, b)
        # macOS rounded window corners include the composited background. JPEG
        # blocks there can differ slightly even with identical window content.
        # Permit only low-amplitude changes confined to those four corners.
        corner = min(64, a.width // 10, a.height // 10)
        content = delta.copy()
        for x, y in [(0, 0), (a.width-corner, 0), (0, a.height-corner), (a.width-corner, a.height-corner)]:
            ImageDraw.Draw(content).rectangle((x, y, x+corner-1, y+corner-1), fill=(0, 0, 0))
        if app == 'Finder' and views and app in views:
            view = views[app]
            win = view['window']
            for el in view['elements']:
                if el.get('role') == 'text' and ' selected, ' in el.get('name', '') and el['name'].endswith(' available'):
                    r = el['rect']
                    sx, sy = a.width / win['w'], a.height / win['h']
                    x, y = (r['x']-win['x'])*sx, (r['y']-win['y'])*sy
                    ImageDraw.Draw(delta).rectangle((x-8, y-8, x+r['width']*sx+8, y+r['height']*sy+8), fill=(0, 0, 0))
        if app == 'Finder' and views and app in views and max(c[1] for c in delta.getextrema()) <= 16:
            bounds = None
        elif app == 'Google Chrome' and content.getbbox() is None and max(channel[1] for channel in delta.getextrema()) <= 32:
            bounds = None
        elif app == 'Google Chrome' and caret_blink(delta, (views or {}).get(app, {})):
            bounds = None
        else:
            bounds = delta.getbbox()
        details[app] = bounds
    return dict(matched=all(v is None for v in details.values()), differences=details)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    try:
        values = json.loads(args.manifest.read_text())
        checkpoint = args.manifest.with_name('baseline.json')
        saved = json.loads(checkpoint.read_text()) if checkpoint.exists() else {}
        views = saved.get('snapshot', {}).get('views') if saved.get('images') == values['baseline'] else None
        print(json.dumps(compare(values['baseline'], values['current'], values.get('masks'), views)))
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps(dict(matched=False, reason=str(error))))
        raise SystemExit(1)
