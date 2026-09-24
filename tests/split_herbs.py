from collections import deque
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DST = ROOT / "assets" / "professions" / "herbalism"
HERBS = [
    "green_leaf",
    "white_flower",
    "red_berry",
    "tall_grass",
    "lavender",
    "mint",
    "dandelion",
    "broad_leaf",
]


def background_candidate(r: int, g: int, b: int, a: int) -> bool:
    if a == 0:
        return True
    high = max(r, g, b)
    low = min(r, g, b)
    chroma = high - low
    return (high >= 175 and chroma <= 28) or (high <= 72 and chroma <= 20)


def clean_icon(image: Image.Image) -> tuple[Image.Image, int]:
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    visited = [[False] * width for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()

    def add(x: int, y: int) -> None:
        if 0 <= x < width and 0 <= y < height and not visited[y][x]:
            r, g, b, a = pixels[x, y]
            if background_candidate(r, g, b, a):
                visited[y][x] = True
                queue.append((x, y))

    for x in range(width):
        add(x, 0)
        add(x, height - 1)
    for y in range(height):
        add(0, y)
        add(width - 1, y)

    removed = 0
    while queue:
        x, y = queue.popleft()
        r, g, b, _ = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        removed += 1
        add(x - 1, y)
        add(x + 1, y)
        add(x, y - 1)
        add(x, y + 1)

    return image, removed


def main() -> None:
    for name in HERBS:
        path = DST / f"{name}.png"
        image, removed = clean_icon(Image.open(path))
        image.save(path, optimize=True)
        alpha = image.getchannel("A")
        transparent = alpha.histogram()[0]
        print(f"{path.name}: removed={removed}, transparent={transparent}/{image.width * image.height}")


if __name__ == "__main__":
    main()
