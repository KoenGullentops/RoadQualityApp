# Road Quality App (Garmin Edge 1030 Plus)

Three Connect IQ **data fields** (a "tile" in your Ride activity screen)
that read the live accelerometer and show a rolling average road-surface
roughness score over three different windows, so they can be mapped
against your GPS track afterwards:

| Project | Tile name | Window |
|---|---|---|
| `fields/roughness-1min/` | Road Roughness (1 min) | trailing 60 seconds |
| `fields/roughness-5min/` | Road Roughness (5 min) | trailing 5 minutes |
| `fields/roughness-trip/` | Road Roughness (Trip)  | cumulative since activity start |

They're three separate, independently-installable apps (Connect IQ data
fields each present as one selectable tile, so three different rolling
windows need three apps) — add any or all of them to your Ride activity
screen's field slots.

## How it works

Each project's `source/RoadQualityField.mc` uses
`Toybox.Sensor.registerSensorDataListener` to read live accelerometer
samples, and once per second (`compute()`) turns them into an instantaneous
roughness value: the RMS of `|acceleration| - 1g` (how far the total
acceleration deviates from gravity). Each tile then folds that
once-per-second value into its own average:

- **1 min / 5 min**: a ring buffer of the last 60 / 300 per-second values,
  averaged (a true sliding window).
- **Trip**: a running sum/count since the field was initialized (i.e.
  since the activity started).

Each tile shows its average on screen and also writes it into the ride's
`.FIT` file every second as its own "developer field"
(`roughness_1min_g` / `roughness_5min_g` / `roughness_trip_g`), via
`Toybox.FitContributor`.

(An earlier version of this project tried to log *raw* accelerometer
samples via `Toybox.SensorLogging.SensorLogger`, which requires the app to
create its own FIT recording session — meaning it had to be a standalone
app, not a data field, and it lost your normal Ride profile's other
fields/screens while recording. `FitContributor`, used here, works from
inside a Data Field precisely because it contributes to a session it
doesn't own, at the cost of only carrying one computed value per second
rather than every raw sample.)

**`tools/fit_to_json.py`** — a Python script you run afterwards on a
computer to parse a ride's `.FIT` file and produce a `.json` file with the
GPS track and whichever of the three rolling averages were active during
that ride. You then move the JSON to your iPhone however you like
(AirDrop, Files, email, etc.).

## Building and installing

Each of the three folders under `fields/` is a self-contained Connect IQ
project (its own `manifest.xml` + `monkey.jungle`). Build and sideload
each one the same way, once per tile you want:

1. Install VS Code + the [Monkey C extension](https://developer.garmin.com/connect-iq/monkey-c/),
   and use its guided setup (SDK Manager → download an SDK → download
   devices → Verify Installation) until "Monkey C: Verify Installation"
   reports success.
2. Command Palette → **"Monkey C: Generate a Developer Key"** (one-time
   for the whole machine; the same key signs all three projects — save the
   `.der` file outside the repo, it's gitignored on purpose).
3. Open one of `fields/roughness-1min/`, `fields/roughness-5min/`, or
   `fields/roughness-trip/` as the VS Code workspace folder (File → Open
   Folder).
4. Command Palette → **"Monkey C: Set Active Device"** → **edge1030plus**.
5. Build: **F5**, or Command Palette → **"Monkey C: Build Current Project"**.
6. Sideload: connect the Edge 1030 Plus over USB, copy the built `.prg`
   into `GARMIN/APPS/` on the device, then eject.
7. Repeat steps 3–6 for the other two folders.
8. On the device: open a Ride activity's field layout editor, and for each
   empty field slot you want to use, choose the matching **Road Roughness
   (…)** entry from the list of data fields.

Each manifest requests only the `Sensor` permission and targets
`minSdkVersion 3.3.0`. I validated the FIT-writing side of this design (all
three developer fields resolving correctly by name, alongside GPS, in the
ride's FIT `record` messages) against the real Garmin FIT field profile
using a synthetic test file, and validated `fit_to_json.py` end-to-end
against it — but the Monkey C source itself hasn't been run in the actual
Connect IQ simulator, so build each one there first and watch for API
errors before your first real ride.

## Recording a ride

Nothing special — start your Ride activity as normal with whichever Road
Roughness tile(s) you added showing on screen. Each updates roughly once a
second.

## Getting the FIT file and converting it

1. Connect the Edge 1030 Plus by USB (or use Garmin Express) and copy the
   activity file out of `GARMIN/ACTIVITY/`.
2. Convert it:
   ```
   pip install -r tools/requirements.txt
   python3 tools/fit_to_json.py path/to/ride.fit ride.json
   ```
3. Move `ride.json` to your iPhone (AirDrop, Files, email, etc.).

### Output JSON shape

```jsonc
{
  "source_fit_file": "ride.fit",
  "generated_at": "2026-08-08T14:52:59+00:00",
  "record_count": 1830,
  "roughness_fields_present": ["roughness_1min_g", "roughness_trip_g"],
  "road_quality": [
    { "timestamp": "2026-08-08T14:52:37+00:00", "epoch": 1786200757.0,
      "lat": 50.85, "lon": 4.35, "speed_mps": 6.1,
      "roughness_1min_g": 0.11, "roughness_5min_g": null, "roughness_trip_g": 0.09 },
    ...
  ]
}
```

`roughness_fields_present` lists only the tiles that actually had a value
on this ride — a field is `null` on every record if that tile wasn't added
to the screen during that ride (FitContributor only writes a value while
its data field is active/showing). If `roughness_fields_present` is empty,
none of the three tiles were on screen for this ride.

## Known caveats

- The roughness score is derived from total acceleration magnitude, not a
  calibrated "vertical" axis — this avoids needing to know the device's
  exact mount angle on the handlebars, since a static 1g reading has the
  same magnitude regardless of orientation.
- The accelerometer's live sample rate/callback cadence is fixed by the
  hardware/firmware; there's no Connect IQ API to request a specific rate.
- The 1-min/5-min windows are sliding windows over the last 60/300
  `compute()` calls, which Connect IQ calls once per second — not
  wall-clock-timestamped, so they assume compute() cadence stays at 1 Hz
  (the documented/standard behavior for data fields).
- This project's Monkey C code was written and reviewed against the public
  Connect IQ API docs and known example patterns (`createField` +
  `FitContributor`, `Sensor.registerSensorDataListener`), but not compiled
  or run in the simulator in the environment this was written in. Build it
  in the simulator before your first real ride.
