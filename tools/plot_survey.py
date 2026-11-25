"""Draw the Gunja building and proposed-site survey using the committed CSVs."""

import csv
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
from matplotlib import font_manager, pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.patches import Patch


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "gunja"


def rings(file, key):
    polygons = defaultdict(list)
    with (DATA / file).open(encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            polygons[tuple(row[k] for k in key)].append((float(row["east_m"]), float(row["north_m"])))
    return list(polygons.values())


def main():
    fonts = font_manager.get_font_names()
    for font in ("Noto Sans CJK KR", "Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK JP"):
        if font in fonts:
            plt.rcParams["font.family"] = font
            break
    shells = rings("buildings.csv", ["building_id"])
    holes = rings("building_holes.csv", ["building_id", "hole_id"])
    with (DATA / "candidates.csv").open(encoding="utf-8") as stream:
        candidates = list(csv.DictReader(stream))

    fig, ax = plt.subplots(figsize=(7.4, 8.0), layout="constrained")
    ax.add_collection(PolyCollection(shells, facecolors="#d4dce0", edgecolors="#89979e", linewidths=.35))
    ax.add_collection(PolyCollection(holes, facecolors="white", edgecolors="#89979e", linewidths=.35))
    xs = [float(row["east_m"]) for row in candidates]
    ys = [float(row["north_m"]) for row in candidates]
    sites = ax.scatter(xs, ys, color="#106862", s=52, edgecolor="white", zorder=4, label="증설 후보")
    for row, x, y in zip(candidates, xs, ys):
        ax.annotate(row["site_id"], (x, y), xytext=(6, 5), textcoords="offset points", size=9,
                    weight="bold", color="#074c48", bbox=dict(fc="white", ec="none", pad=1, alpha=.88))
    origin = ax.scatter(0, 0, marker="*", color="#a3361b", s=175, zorder=5,
                        edgecolor="white", linewidth=.7, label="군자역 기준점")
    ax.set(xlim=(-300, 300), ylim=(-300, 300), aspect="equal", xlabel="동쪽 거리 (m)", ylabel="북쪽 거리 (m)")
    ax.set_title("군자역 지상 건물과 기지국 증설 후보", loc="left", size=18, pad=16)
    ax.legend(handles=[origin, sites, Patch(facecolor="#d4dce0", edgecolor="#89979e", label="건물 윤곽")],
              loc="upper center", bbox_to_anchor=(.5, -.09), ncol=3, frameon=False)
    output = ROOT / "reports" / "gunja" / "building_survey.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=175, bbox_inches="tight", facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    main()
