#!/usr/bin/env python3
"""
Convert a Road Quality FIT file into a JSON file with the GPS track and
whichever road-roughness developer fields are present, written by either:

- app/ (standalone app, own recording session): roughness_raw_g (the
  unsmoothed instantaneous reading), roughness_1min_g, roughness_5min_g,
  roughness_trip_g, continuously updated every second, plus the raw
  per-axis accel_x_g/accel_y_g/accel_z_g (per-second averages, in g).
- datafield/ (Data Field tile on a normal Ride activity): roughness_snapshot_g
  (a background-sampled snapshot updated roughly every 5 minutes) and
  roughness_trip_avg_g (the running average of all snapshots so far this trip).

A given ride's FIT file will normally have one set or the other, not both,
depending on which was used to record it.

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

# Developer field name -> the JSON key it's reported under.
ROUGHNESS_FIELDS = {
    "roughness_raw_g": "roughness_raw_g",
    "roughness_1min_g": "roughness_1min_g",
    "roughness_5min_g": "roughness_5min_g",
    "roughness_trip_g": "roughness_trip_g",
    "roughness_snapshot_g": "roughness_snapshot_g",
    "roughness_trip_avg_g": "roughness_trip_avg_g",
}

# app/'s raw per-axis accelerometer readings (per-second average, in g),
# written alongside the roughness fields above - kept in a separate dict
# since these aren't a roughness metric themselves and shouldn't affect
# roughness_fields_present or docs/'s metric picker.
AXIS_FIELDS = {
    "accel_x_g": "accel_x_g",
    "accel_y_g": "accel_y_g",
    "accel_z_g": "accel_z_g",
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
        for field_name, json_key in AXIS_FIELDS.items():
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
    present_axis_fields = [
        json_key for json_key in AXIS_FIELDS.values()
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
        "axis_fields_present": present_axis_fields,
        "road_quality": records,
    }

    with open(args.json_file, "w") as f:
        json.dump(output, f, indent=2)

    print("Wrote {} records to {} (roughness fields present: {}; axis fields present: {})".format(
        len(records), args.json_file, ", ".join(present_fields) or "none",
        ", ".join(present_axis_fields) or "none"))


if __name__ == "__main__":
    main()
