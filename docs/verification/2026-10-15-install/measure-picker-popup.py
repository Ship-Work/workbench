# Right edge, in points (2x renders), of the Prompts picker's category pop-up and of its footer button.
import sys
from PIL import Image
def differs(p, q, limit=14): return max(abs(a - b) for a, b in zip(p, q)) > limit
def measure(path):
    im = Image.open(path).convert('RGB'); w, h = im.size; px = im.load()
    mid = h // 2
    # The panel's right border: the first change from the outside background, walking in from the right.
    panel = next((x for x in range(w - 2, w // 2, -1) if differs(px[x, mid], px[w - 1, mid], 4)), w - 1)
    def edge(rows):
        best = 0
        for y in rows:
            bg = px[panel - 8, y]
            for x in range(panel - 9, w // 2, -1):
                if differs(px[x, y], bg): best = max(best, x); break
        return best
    # The header sits in the top 100 px of the panel and the footer button in the bottom 100.
    top = next(y for y in range(h) if differs(px[w // 2, y], px[w // 2, 0], 4))
    bottom = next(y for y in range(h - 1, 0, -1) if differs(px[w // 2, y], px[w // 2, h - 1], 4))
    return edge(range(top + 10, top + 70)), edge(range(bottom - 70, bottom - 12))
for folder in sys.argv[1:]:
    for f in ['picker-host-open', 'picker-grouped', 'picker-filtered', 'picker-long-names']:
        for theme in ['light', 'dark']:
            popup, button = measure(f"{folder}/{f}-{theme}.png")
            print(f"{folder.rsplit('/',1)[-1]:16} {f+'-'+theme:24} pop-up {popup/2:6.1f} pt  button {button/2:6.1f} pt  gap {(button-popup)/2:5.1f} pt")
