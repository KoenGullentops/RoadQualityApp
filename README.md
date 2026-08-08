# Road Quality App (Garmin Edge 1030 Plus)

A Connect IQ **data field** (a "tile" in your Ride activity screen) that
reads the live accelerometer and shows a rolling road-surface roughness
score, so it can be mapped against your GPS track afterwards.

## How it works

1. **`source/*.mc`** — a Connect IQ data field for the Edge 1030 Plus. Add
   it to a field slot on your normal Ride activity screen like any other
   data field (speed, power, etc.) — no separate app to launch. It uses
   `Toybox.Sensor.registerSensorDataListener` to read live accelerometer
   samples, and once per second computes the RMS of `|acceleration| - 1g`
   (how far the total acceleration deviates from gravity) as a roughness
   score. That score is shown on the tile and also written into the ride's
   `.FIT` file each second as a custom "developer field" named
   `road_roughness`, via `Toybox.FitContributor`.

   (An earlier version of this project tried to log *raw* accelerometer
   samples via `Toybox.SensorLogging.SensorLogger`, which requires the app
   to create its own FIT recording session — meaning it had to be a
   standalone app, not a data field, and it lost your normal Ride profile's
   other fields/screens while recording. `FitContributor`, used here,
   works from inside a Data Field precisely because it contributes to a
   session it doesn't own, at the cost of only carrying one computed value
   per second rather than every raw sample.)

2. **`tools/fit_to_json.py`** — a Python script you run afterwards on a
   computer to parse that `.FIT` file and produce a `.json` file with the
   GPS track and the per-second roughness score. You then move the JSON to
   your iPhone however you like (AirDrop, Files, email, etc.).

## Building and installing

1. Install VS Code + the [Monkey C extension](https://developer.garmin.com/connect-iq/monkey-c/),
   and use its guided setup (SDK Manager → download an SDK → download
   devices → Verify Installation) until "Monkey C: Verify Installation"
   reports success.
2. Open this folder as the project root (it has `manifest.xml` and
   `monkey.jungle` already).
3. Command Palette → **"Monkey C: Generate a Developer Key"** (one-time;
   save the `.der` file outside the repo).
4. Command Palette → **"Monkey C: Set Active Device"** → **edge1030plus**.
5. Build: **F5**, or Command Palette → **"Monkey C: Build Current Project"**.
6. Sideload: connect the Edge 1030 Plus over USB, copy the built `.prg`
   into `GARMIN/APPS/` on the device, then eject.
7. On the device: open a Ride activity's field layout editor, find an empty
   field slot, and choose **Road Quality** from the list of data fields to
   add it.

The manifest requests only the `Sensor` permission and targets
`minSdkVersion 3.3.0`. I validated the FIT-writing side of this design
(the `road_roughness` developer field resolving correctly, alongside GPS,
in the ride's FIT `record` messages) against the real Garmin FIT field
profile using a synthetic test file, and validated `fit_to_json.py`
end-to-end against it — but the Monkey C source itself hasn't been run in
the actual Connect IQ simulator, so build it there first and watch for API
errors before your first real ride.

## Recording a ride

Nothing special — start your Ride activity as normal with the Road Quality
field showing on screen. It updates roughly once a second.

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
  "records_with_roughness": 1830,
  "road_quality": [
    { "timestamp": "2026-08-08T14:52:37+00:00", "epoch": 1786200757.0,
      "lat": 50.85, "lon": 4.35, "speed_mps": 6.1, "roughness_g": 0.12 },
    ...
  ]
}
```

If `records_with_roughness` is 0, the Road Quality field probably wasn't
actually on screen during that ride (FitContributor only writes a value
while its data field is active/showing).

## Known caveats

- The roughness score is derived from total acceleration magnitude, not a
  calibrated "vertical" axis — this avoids needing to know the device's
  exact mount angle on the handlebars, since a static 1g reading has the
  same magnitude regardless of orientation.
- The accelerometer's live sample rate/callback cadence is fixed by the
  hardware/firmware; there's no Connect IQ API to request a specific rate.
- This project's Monkey C code was written and reviewed against the public
  Connect IQ API docs and known example patterns (`createField` +
  `FitContributor`, `Sensor.registerSensorDataListener`), but not compiled
  or run in the simulator in the environment this was written in. Build it
  in the simulator before your first real ride.
