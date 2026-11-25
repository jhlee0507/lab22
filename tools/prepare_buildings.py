"""Extract Seoul building footprints in the station's local east/north coordinates."""

import argparse
import csv
import hashlib
from pathlib import Path

import numpy as np
import pyarrow.parquet as pq
from pyproj import Transformer
from shapely import Point, Polygon, box, transform


ROOT = Path(__file__).resolve().parents[1]
SURVEY = ROOT / "data" / "gunja"
SOURCE_SHA256 = "9dd7e12faa9d774f4fb2ebf6a1004f613bb336be64ee9edad552b45e9a0f96f0"
HALF_WIDTH_M = 300


def local_projection():
    with (SURVEY / "origin.csv").open(encoding="utf-8") as source:
        origin = next(csv.DictReader(source))
    return Transformer.from_pipeline(
        "+proj=pipeline +step +proj=unitconvert +xy_in=deg +xy_out=rad "
        "+step +proj=cart +ellps=WGS84 +step +proj=topocentric +ellps=WGS84 "
        f"+lat_0={origin['latitude_deg']} +lon_0={origin['longitude_deg']} +h_0=0"
    )


def nearby_rows(geometries, bounds):
    """Compute each GeoArrow multipolygon's bounds before decoding its rings."""
    parts = geometries.flatten()
    rings = parts.flatten()
    points = rings.flatten()
    xy = points.flatten().to_numpy().reshape(-1, 2)
    offsets = []
    for array in (rings, parts, geometries):
        offsets.append(np.asarray(array.offsets) - array.offsets[0].as_py())
    starts = offsets[0][offsets[1][offsets[2]]]
    # The sentinel handles empty geometries at the end of a batch.
    lo = np.minimum.reduceat(np.vstack((xy, [np.inf, np.inf])), starts[:-1], axis=0)
    hi = np.maximum.reduceat(np.vstack((xy, [-np.inf, -np.inf])), starts[:-1], axis=0)
    west, south, east, north = bounds
    return np.flatnonzero(
        (np.diff(starts) > 0) & (lo[:, 0] <= east) & (hi[:, 0] >= west)
        & (lo[:, 1] <= north) & (hi[:, 1] >= south)
    )


def extract(source):
    with source.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError("Input does not match the documented Seoul building snapshot.")
    projection = local_projection()
    extent = box(-HALF_WIDTH_M, -HALF_WIDTH_M, HALF_WIDTH_M, HALF_WIDTH_M)
    corners = [projection.transform(x, y, 0, direction="INVERSE")
               for x, y in extent.exterior.coords]
    # A conservative spatial prefilter. The final intersection is in metres.
    lons, lats, _ = zip(*corners)
    bounds = min(lons)-0.0001, min(lats)-0.0001, max(lons)+0.0001, max(lats)+0.0001
    footprints = {}
    row_offset = 0
    for batch in pq.ParquetFile(source).iter_batches(batch_size=8192, columns=["geometry"]):
        geometries = batch.column(0)
        for row in nearby_rows(geometries, bounds):
            for part, rings in enumerate(geometries[int(row)].as_py(), start=1):
                geometry = transform(Polygon(rings[0], rings[1:]), projection.transform, interleaved=False)
                if not geometry.intersects(extent):
                    continue
                if not geometry.is_valid:
                    raise ValueError(f"Invalid source building at row {row_offset + row + 1}.")
                if geometry.intersection(extent).area > 0:
                    footprints[f"B{row_offset + row + 1:06d}-{part}"] = geometry
        row_offset += len(geometries)
    if not footprints:
        raise ValueError("No building intersects the study area.")
    return footprints


def write_footprints(footprints, output):
    output.mkdir(parents=True, exist_ok=True)
    with (output / "buildings.csv").open("w", newline="") as shells, (
        output / "building_holes.csv"
    ).open("w", newline="") as holes:
        outer = csv.writer(shells, lineterminator="\n")
        inner = csv.writer(holes, lineterminator="\n")
        outer.writerow(["building_id", "east_m", "north_m"])
        inner.writerow(["building_id", "hole_id", "east_m", "north_m"])
        for key, geometry in footprints.items():
            for x, y in list(geometry.exterior.coords)[:-1]:
                outer.writerow([key, f"{x:.2f}", f"{y:.2f}"])
            for ring_id, ring in enumerate(geometry.interiors, start=1):
                for x, y in list(ring.coords)[:-1]:
                    inner.writerow([key, ring_id, f"{x:.2f}", f"{y:.2f}"])


def write_candidates(footprints, output):
    """One distinct building per 200 m grid cell, before checking radio sites."""
    projection = local_projection()
    choices = {key: geom.representative_point() for key, geom in footprints.items()
               if geom.area >= 150}
    with (output / "candidates.csv").open("w", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["site_id", "building_id", "east_m", "north_m", "longitude_deg", "latitude_deg"])
        index = 0
        for north in (200, 0, -200):
            for east in (-200, 0, 200):
                index += 1
                center = Point(east, north)
                eligible = [key for key, p in choices.items()
                            if abs(p.x-east) < 100 and abs(p.y-north) < 100]
                if not eligible:
                    raise ValueError(f"No eligible building in the cell around {east}, {north}.")
                building_id = min(eligible, key=lambda key: (choices[key].distance(center), key))
                p = choices[building_id]
                lon, lat, _ = projection.transform(p.x, p.y, 0, direction="INVERSE")
                writer.writerow([f"P{index:02d}", building_id, f"{p.x:.2f}", f"{p.y:.2f}",
                                 f"{lon:.7f}", f"{lat:.7f}"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parquet", type=Path)
    parser.add_argument("--output", type=Path, default=SURVEY)
    args = parser.parse_args()
    polygons = extract(args.parquet)
    write_footprints(polygons, args.output)
    write_candidates(polygons, args.output)
    print(f"{len(polygons)} footprint parts, {sum(len(p.interiors) for p in polygons.values())} interior rings")
