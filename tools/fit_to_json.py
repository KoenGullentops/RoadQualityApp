#!/usr/bin/env python3
"""
Convert a Road Quality FIT file (recorded with the RoadQualityApp Connect IQ
data field active on a ride) into a JSON file with the GPS track and the
per-second road-roughness score the data field computed and wrote into the
FIT file as a developer field named "road_roughness".

Usage:
    python3 fit_to_json.py ride.fit ride.json

Requires: fitparse (pip install fitparse)
"""

import argparse
import json
import sys
from datetime import datetime, timezone

from fitparse import FitFile

RECORD_MESG = "record"
ROUGHNESS_FIELD_NAME = "road_roughness"
SEMICIRCLE_TO_DEG = 180.0 / (2 ** 31)


def iso(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def read_records(fit):
    records = []
    for msg in fit.get_messages(RECORD_MESG):
        values = msg.get_values()
        ts = values.get("timestamp")
        if not isinstance(ts, datetime):
            continue

        lat = values.get("position_lat")
        lon = values.get("position_long")
        speed = values.get("enhanced_speed")
        if speed is None:
            speed = values.get("speed")

        records.append({
            "timestamp": iso(ts),
            "epoch": ts.timestamp(),
            "lat": lat * SEMICIRCLE_TO_DEG if lat is not None else None,
            "lon": lon * SEMICIRCLE_TO_DEG if lon is not None else None,
            "speed_mps": speed,
            "roughness_g": values.get(ROUGHNESS_FIELD_NAME),
        })

    records.sort(key=lambda r: r["epoch"])
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fit_file", help="Path to the recorded .FIT file")
    parser.add_argument("json_file", help="Path to write the output .json file")
    args = parser.parse_args()

    fit = FitFile(args.fit_file)
    fit.parse()

    records = read_records(fit)
    with_roughness = [r for r in records if r["roughness_g"] is not None]

    if not with_roughness:
        print("Warning: no records with a 'road_roughness' developer field were found. "
              "Was the Road Quality data field actually added to the activity screen "
              "during this ride?", file=sys.stderr)

    output = {
        "source_fit_file": args.fit_file,
        "generated_at": iso(datetime.now(tz=timezone.utc)),
        "record_count": len(records),
        "records_with_roughness": len(with_roughness),
        "road_quality": records,
    }

    with open(args.json_file, "w") as f:
        json.dump(output, f, indent=2)

    print("Wrote {} records ({} with a road-roughness value) to {}".format(
        len(records), len(with_roughness), args.json_file))


if __name__ == "__main__":
    main()
