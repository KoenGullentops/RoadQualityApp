# Road Quality App (Garmin Edge 1030 Plus)

Records raw accelerometer data during a ride and turns it into a JSON file
you can move to your iPhone, so road-surface roughness can be mapped
against your GPS track.

## How it works

Connect IQ (the Garmin app platform) has no public API for a third-party
app to write an arbitrary `.json` file to USB-visible storage, and a Data
Field embedded in your normal Ride profile can't attach a raw-accelerometer
logger — that can only be done by the app that *creates* the activity
recording session. So this is split into two pieces:

1. **`source/*.mc`** — a standalone Connect IQ watch app (not a data field)
   for the Edge 1030 Plus. Press **Select** to start; it creates its own FIT
   activity-recording session with `Toybox.SensorLogging.SensorLogger`
   attached, which logs raw accelerometer samples (x/y/z, in g) directly
   into the ride's `.FIT` file at ~25 Hz, alongside the normal GPS/speed
   records. Press **Select** again to stop and save. Since you launch this
   app instead of your normal Ride profile, it's your only on-screen field
   during the recording.
2. **`tools/fit_to_json.py`** — a Python script you run afterwards on a
   computer to parse that `.FIT` file and produce the `.json` file, with
   per-sample accelerometer data, the GPS track, and a derived per-second
   road-roughness score. You then move the JSON to your iPhone however you
   like (AirDrop, Files, email, etc.).

## Building and installing the watch app

1. Install VS Code + the [Monkey C extension](https://developer.garmin.com/connect-iq/monkey-c/)
   (or the standalone Connect IQ SDK Manager) and accept the SDK license.
2. Open this folder as the project root (it already has `manifest.xml` and
   `monkey.jungle`).
3. Build for the **Edge 1030 Plus** device, either via the VS Code command
   "Monkey C: Build Current Project" or from the CLI:
   ```
   monkeyc -f monkey.jungle -o bin/RoadQualityApp.prg -d edge1030plus -y developer_key.der
   ```
   (Generate `developer_key.der` once via "Monkey C: New Project"/`monkeyc --generate-key` if you don't already have a signing key.)
4. Sideload it: connect the Edge 1030 Plus over USB and copy
   `bin/RoadQualityApp.prg` into the `GARMIN/APPS/` folder on the device,
   then eject/disconnect.
5. On the device, open the apps menu and launch **Road Quality**.

The manifest requests the `Sensor`, `Positioning`, and `ActivityRecording`
permissions and targets `minSdkVersion 3.3.0`, which the Edge 1030 Plus
supports. If your installed SDK reports a different minimum for
`SensorLogging`/`getStats2`, adjust `minSdkVersion` in `manifest.xml`
accordingly — I couldn't compile-test this against the real SDK/simulator
in the environment this was written in, so treat the on-device sample-count
display in `RoadQualityRecorder.getSampleCountString()` as best-effort; it's
wrapped so a field-name mismatch there degrades to a blank line instead of
crashing the app.

## Recording a ride

1. Mount the Edge 1030 Plus as usual.
2. Launch **Road Quality** and press **Select** to start. The screen shows
   "RECORDING", elapsed time, and a running sample count.
3. Ride. GPS gets a normal fix as usual; the accelerometer logs continuously
   in the background.
4. Press **Select** again to stop (this also saves the FIT file). Pressing
   **Back** while recording also stops and saves, rather than exiting over
   an open session.

## Getting the FIT file and converting it

1. Connect the Edge 1030 Plus by USB (or use Garmin Express) and copy the
   new activity file out of `GARMIN/ACTIVITY/`.
2. Convert it:
   ```
   pip install -r tools/requirements.txt
   python3 tools/fit_to_json.py path/to/ride.fit ride.json
   ```
3. Move `ride.json` to your iPhone (AirDrop from the same Mac, Files app,
   email, etc.).

`fit_to_json.py` options:
- `--sample-rate` — nominal accelerometer rate in Hz, used only as a
  fallback when a burst's sample timestamps are missing (default 25; some
  devices report closer to ~24.3 Hz in practice — this doesn't affect
  samples that do have valid offsets).
- `--window` — size in seconds of each road-quality scoring window
  (default 1.0).
- `--no-raw-samples` — omit the full per-sample array from the output and
  keep just the GPS track and the per-window roughness scores, for a much
  smaller file.

### Output JSON shape

```jsonc
{
  "source_fit_file": "ride.fit",
  "generated_at": "2026-08-04T19:57:00+00:00",
  "accelerometer": {
    "unit": "g",
    "nominal_sample_rate_hz": 25.0,
    "sample_count": 4820,
    "samples": [
      { "seq": 0, "epoch": 1785873420.0, "timestamp": "2026-08-04T19:57:00+00:00",
        "x_g": 0.01, "y_g": -0.02, "z_g": 0.98 },
      ...
    ]
  },
  "gps_track": [
    { "epoch": 1785873420.0, "timestamp": "...", "lat": 50.8503, "lon": 4.3517, "speed_mps": 6.1 },
    ...
  ],
  "road_quality": [
    { "window_start_epoch": 1785873420.0, "window_start": "...",
      "sample_count": 25, "roughness_rms_g": 0.12,
      "lat": 50.8503, "lon": 4.3517, "speed_mps": 6.1 },
    ...
  ]
}
```

`roughness_rms_g` is the RMS, over that window, of `|accel_vector| - 1g` —
i.e. how far the total acceleration magnitude deviates from gravity. Using
the vector magnitude (rather than trying to isolate the "vertical" axis)
sidesteps not knowing the device's exact mount angle on the handlebars,
since a static 1g reading has the same magnitude regardless of orientation.

## Known caveats

- Some Garmin firmware versions have a bug where the `timestamp` field on
  `accelerometer_data` FIT messages doesn't hold a real time value. The
  conversion script detects this (falls back to numbering samples
  sequentially at the nominal sample rate) so the output still has sane,
  monotonic timestamps, but they won't be wall-clock-accurate if this
  firmware bug is present on your device.
- Sample rate is fixed by the hardware/firmware at roughly 25 Hz; there's no
  Connect IQ API to request a different rate.
- This project's Monkey C code was written and reviewed against the public
  Connect IQ API docs and known example code, but not compiled or run in
  the simulator (no Connect IQ SDK in this environment). Build it in the
  simulator before your first real ride and watch the console for API
  errors — most likely spot for drift is `getStats2()`'s exact stats field
  names.
