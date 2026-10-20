"""Snap grid probe: each card's Copy-button band and bottom border row, from the thumbnail columns."""
import sys
from PIL import Image

def runs(im, x, y0, y1):
    out, prev, start = [], None, y0
    for y in range(y0, y1):
        c = im.getpixel((x, y))
        if c != prev:
            if prev is not None: out.append((start, y - 1, prev))
            prev, start = c, y
    out.append((start, y1 - 1, prev))
    return out

def probe(path):
    im = Image.open(path).convert('RGB'); w, h = im.size
    # Thumbnails: the long non-neutral runs across the row through their middle.
    y = 700; xs, start = [], None
    for x in range(w):
        r, g, b = im.getpixel((x, y)); coloured = max(r, g, b) - min(r, g, b) > 25
        if coloured and start is None: start = x
        if not coloured and start is not None:
            if x - start > 200: xs.append((start, x - 1))
            start = None
    cards = []
    for x0, x1 in xs:
        column = runs(im, x0 + 8, 820, 1150)
        lengths = {}
        for a, b, c in column: lengths[c] = lengths.get(c, 0) + b - a + 1
        surface = max(lengths, key=lengths.get)  # the card and page share the most rows
        band = [r for r in column if 30 <= r[1] - r[0] <= 50 and r[2] != surface]
        copy = (band[0][0], band[0][1]) if band else None
        col = runs(im, x0 + int((x1 - x0) * 0.62), 820, 1150)
        bg = col[-1][2]
        # The bottom border: the last row before the trailing page background.
        bottom = col[-2][1] if len(col) > 1 else None
        cards.append((x0, copy, bottom))
    return cards

for path in sys.argv[1:]:
    cards = probe(path)
    copies = [c[1] for c in cards]; bottoms = [c[2] for c in cards]
    level = all(c and abs(c[0] - copies[0][0]) <= 1 and abs(c[1] - copies[0][1]) <= 1 for c in copies) and max(bottoms) - min(bottoms) <= 1
    print(path.split('/')[-1], 'cards', [c[0] for c in cards], 'copy rows', copies, 'bottoms', bottoms, 'LEVEL' if level else 'RAGGED')
