#!/usr/bin/env python3
"""
Convert a Road Quality FIT file (recorded with the RoadQualityApp Connect IQ
app) into a JSON file with the GPS track and the three rolling
road-roughness averages (1 min / 5 min / trip) the app wrote into the FIT
file as developer fields.

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
SEMICIRCLE_TO_DEG = 180.0 / (2 ** 31)

# Developer field name -> the JSON key it's reported under. All three are
# written by the same app/session, so they're normally all present together.
ROUGHNESS_FIELDS = {
    "roughness_1min_g": "roughness_1min_g",
    "roughness_5min_g": "roughness_5min_g",
    "roughness_trip_g": "roughness_trip_g",
}


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

        record = {
            "timestamp": iso(ts),
            "epoch": ts.timestamp(),
            "lat": lat * SEMICIRCLE_TO_DEG if lat is not None else None,
            "lon": lon * SEMICIRCLE_TO_DEG if lon is not None else None,
            "speed_mps": speed,
        }
        for field_name, json_key in ROUGHNESS_FIELDS.items():
            record[json_key] = values.get(field_name)

        records.append(record)

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

    present_fields = [
        json_key for json_key in ROUGHNESS_FIELDS.values()
        if any(r[json_key] is not None for r in records)
    ]

    if not present_fields:
        print("Warning: no records with any road-roughness developer field were found. "
              "Was this ride recorded with the Road Quality app?", file=sys.stderr)

    output = {
        "source_fit_file": args.fit_file,
        "generated_at": iso(datetime.now(tz=timezone.utc)),
        "record_count": len(records),
        "roughness_fields_present": present_fields,
        "road_quality": records,
    }

    with open(args.json_file, "w") as f:
        json.dump(output, f, indent=2)

    print("Wrote {} records to {} (roughness fields present: {})".format(
        len(records), args.json_file, ", ".join(present_fields) or "none"))


if __name__ == "__main__":
    main()
