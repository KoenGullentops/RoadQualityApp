#!/usr/bin/env python3
"""
Convert a Road Quality FIT file (recorded by the RoadQualityApp Connect IQ
app) into a JSON file with per-sample accelerometer data, the GPS track, and
a derived per-second road-roughness score.

Usage:
    python3 fit_to_json.py ride.fit ride.json
    python3 fit_to_json.py ride.fit ride.json --sample-rate 25 --window 1.0

Requires: fitparse (pip install fitparse)
"""

import argparse
import json
import math
import sys
from collections import defaultdict
from datetime import datetime, timezone

from fitparse import FitFile

ACCEL_MESG = "accelerometer_data"
RECORD_MESG = "record"
NOMINAL_SAMPLE_RATE_HZ = 25.0
GRAVITY_G = 1.0


def iso(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def read_accelerometer_samples(fit, sample_rate_hz):
    """Flatten accelerometer_data messages (each holding a burst of samples
    with millisecond offsets) into one ordered list of individual samples.
    """
    samples = []
    fallback_seq = 0
    fallback_start = None

    for msg in fit.get_messages(ACCEL_MESG):
        values = msg.get_values()
        base_ts = values.get("timestamp")
        offsets = values.get("sample_time_offset")
        xs = values.get("calibrated_accel_x")
        ys = values.get("calibrated_accel_y")
        zs = values.get("calibrated_accel_z")

        if xs is None or ys is None or zs is None:
            continue

        # A message can hold either a single sample (scalars) or a burst
        # (tuples); normalize to tuples.
        if not isinstance(xs, (tuple, list)):
            xs, ys, zs = (xs,), (ys,), (zs,)
            offsets = (offsets,) if offsets is not None else (0,)
        if offsets is None or len(offsets) != len(xs):
            offsets = [i * (1000.0 / sample_rate_hz) for i in range(len(xs))]

        for x, y, z, off_ms in zip(xs, ys, zs, offsets):
            if x is None or y is None or z is None:
                continue

            timestamp = None
            # Known firmware bug: this timestamp is sometimes garbage.
            # Only trust it if it's a real datetime.
            if isinstance(base_ts, datetime):
                timestamp = base_ts.timestamp() + (off_ms or 0) / 1000.0
            else:
                if fallback_start is None:
                    fallback_start = 0.0
                timestamp = None

            samples.append({
                "seq": fallback_seq,
                "epoch": timestamp,
                "x_g": x,
                "y_g": y,
                "z_g": z,
            })
            fallback_seq += 1

    # If none of the messages carried a usable timestamp, synthesize one
    # from sequence number and the assumed sample rate so downstream
    # windowing still works.
    if samples and all(s["epoch"] is None for s in samples):
        for s in samples:
            s["epoch"] = s["seq"] / sample_rate_hz

    return samples


def read_gps_track(fit):
    track = []
    semicircle_to_deg = 180.0 / (2 ** 31)
    for msg in fit.get_messages(RECORD_MESG):
        values = msg.get_values()
        lat = values.get("position_lat")
        lon = values.get("position_long")
        ts = values.get("timestamp")
        if lat is None or lon is None or not isinstance(ts, datetime):
            continue
        speed = values.get("enhanced_speed")
        if speed is None:
            speed = values.get("speed")
        track.append({
            "epoch": ts.timestamp(),
            "timestamp": iso(ts),
            "lat": lat * semicircle_to_deg,
            "lon": lon * semicircle_to_deg,
            "speed_mps": speed,
        })
    track.sort(key=lambda r: r["epoch"])
    return track


def nearest_gps(track, epoch):
    if not track:
        return None
    # track is sorted by epoch; linear scan is fine at this data volume.
    best = min(track, key=lambda r: abs(r["epoch"] - epoch))
    return best


def compute_road_quality(samples, gps_track, window_seconds):
    if not samples:
        return []

    buckets = defaultdict(list)
    t0 = samples[0]["epoch"]
    for s in samples:
        bucket_idx = int((s["epoch"] - t0) // window_seconds)
        buckets[bucket_idx].append(s)

    windows = []
    for idx in sorted(buckets.keys()):
        bucket = buckets[idx]
        deviations = []
        for s in bucket:
            magnitude = math.sqrt(s["x_g"] ** 2 + s["y_g"] ** 2 + s["z_g"] ** 2)
            deviations.append(magnitude - GRAVITY_G)
        rms = math.sqrt(sum(d * d for d in deviations) / len(deviations))
        window_epoch = t0 + idx * window_seconds
        gps = nearest_gps(gps_track, window_epoch)

        windows.append({
            "window_start_epoch": window_epoch,
            "window_start": iso(datetime.fromtimestamp(window_epoch, tz=timezone.utc)),
            "sample_count": len(bucket),
            "roughness_rms_g": rms,
            "lat": gps["lat"] if gps else None,
            "lon": gps["lon"] if gps else None,
            "speed_mps": gps["speed_mps"] if gps else None,
        })

    return windows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fit_file", help="Path to the recorded .FIT file")
    parser.add_argument("json_file", help="Path to write the output .json file")
    parser.add_argument("--sample-rate", type=float, default=NOMINAL_SAMPLE_RATE_HZ,
                         help="Nominal accelerometer sample rate in Hz (default: 25)")
    parser.add_argument("--window", type=float, default=1.0,
                         help="Road-quality scoring window, in seconds (default: 1.0)")
    parser.add_argument("--no-raw-samples", action="store_true",
                         help="Omit the full per-sample accelerometer array from the output "
                              "(keeps just the road_quality windows and GPS track)")
    args = parser.parse_args()

    fit = FitFile(args.fit_file)
    fit.parse()

    samples = read_accelerometer_samples(fit, args.sample_rate)
    gps_track = read_gps_track(fit)
    road_quality = compute_road_quality(samples, gps_track, args.window)

    if not samples:
        print("Warning: no accelerometer_data messages found in this FIT file.",
              file=sys.stderr)

    output = {
        "source_fit_file": args.fit_file,
        "generated_at": iso(datetime.now(tz=timezone.utc)),
        "accelerometer": {
            "unit": "g",
            "nominal_sample_rate_hz": args.sample_rate,
            "sample_count": len(samples),
        },
        "gps_track": gps_track,
        "road_quality": road_quality,
    }

    if not args.no_raw_samples:
        output["accelerometer"]["samples"] = [
            {
                "seq": s["seq"],
                "epoch": s["epoch"],
                "timestamp": iso(datetime.fromtimestamp(s["epoch"], tz=timezone.utc)) if s["epoch"] is not None else None,
                "x_g": s["x_g"],
                "y_g": s["y_g"],
                "z_g": s["z_g"],
            }
            for s in samples
        ]

    with open(args.json_file, "w") as f:
        json.dump(output, f, indent=2)

    print("Wrote {} accelerometer samples, {} GPS points, {} road-quality windows to {}".format(
        len(samples), len(gps_track), len(road_quality), args.json_file))


if __name__ == "__main__":
    main()
