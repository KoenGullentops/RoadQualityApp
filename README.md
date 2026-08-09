# DS2.0 Road Quality Index (Garmin Edge 1030 Plus)

A standalone Connect IQ **watch app** that reads the live accelerometer
during a ride and shows three rolling road-surface roughness averages —
last 1 minute, last 5 minutes, and since the ride started — plus a live
graph of the raw reading across the whole trip, so it can be mapped
against your GPS track afterwards.

## Why a standalone app, not a data field

This started as a Data Field ("tile" you add to your normal Ride activity
screen), but that turned out to be architecturally impossible on this
device: **Data Fields cannot read accelerometer data on Edge devices, by
any method.** This was confirmed directly, from an on-device crash log:

```
Error: Permission Required
Details: "Symbol 'registerSensorDataListener' not available to 'Data Field'"
```

and independently corroborated by other developers' reports that the
older polling API (`Sensor.getInfo()`) crashes from a Data Field too, and
that `SensorHistory` (which would have been a workaround, since it logs
sensor data at the OS level regardless of which app is in the foreground)
doesn't exist on Edge devices at all.

The only Connect IQ app type that can read live accelerometer data is one
that owns its own `Toybox.ActivityRecording` session — i.e. a standalone
app, not a data field. The trade-off: you start "DS2.0 Road Quality Index"
as its own recording instead of adding it to your existing Ride activity
profile, so you won't see your other usual fields (power, HR zones, maps,
etc.) while it's recording. This isn't a limitation of our code, either —
Garmin's background execution API (`Toybox.Background`) enforces a hard
minimum 5-minute wake interval on Edge devices, nowhere near what
continuous per-second sampling needs, so there's no way to run this
alongside your normal Ride profile even via a background service.

## How it works

- **`source/RoadQualityRecorder.mc`** — owns the FIT recording session,
  reads live accelerometer via `Sensor.registerSensorDataListener` (which
  *is* allowed for a plain watch app), and once per second (via a 1 Hz
  timer) turns the accumulated samples into an instantaneous roughness
  value: the RMS of `|acceleration| - 1g` (how far the total acceleration
  deviates from gravity). That value then feeds three running averages:
  - **1 min / 5 min**: a ring buffer of the last 60 / 300 per-second
    values (a true sliding window, O(1) per update).
  - **Trip**: a running sum/count since recording started.

  All three are written into the session's FIT file every second as
  developer fields (`roughness_1min_g`, `roughness_5min_g`,
  `roughness_trip_g`) via `Toybox.FitContributor`. The same per-second
  instantaneous reading also feeds a whole-trip history graph: a
  120-point buffer that automatically halves its own resolution (doubling
  seconds-per-point) whenever it fills up, so a ride of any length fits
  in a fixed amount of memory — recent history at higher resolution,
  older history coarser, same idea as how a browser's zoomed-out
  performance graph works.
- **`source/RoadQualityView.mc`** — the main screen: recording status, the
  three current values, the live history graph, and a large 2x2 grid
  (speed, distance, elapsed time, heart rate) filling the space below,
  read from `Activity.getActivityInfo()`.
- **`source/RoadQualityDelegate.mc`** — tap the screen (or press the
  physical select button) to start recording; tap again to stop and save.
  Swipe or press the page button to open the map screen.
- **`source/RoadQualityMapView.mc`** / **`RoadQualityMapDelegate.mc`** — a
  second screen showing a real onboard map (`Toybox.WatchUi.MapView`,
  available on devices with onboard cartography like the Edge 1030 Plus),
  in `MAP_MODE_BROWSE` (full cartography, not the simplified
  `MAP_MODE_PREVIEW`), with your GPS breadcrumb trail for the trip drawn
  on top as a polyline. Tap, select, or back returns to the main screen.

  **A pre-planned route/GPX course cannot be drawn here** — confirmed
  against the local Connect IQ SDK docs, `PersistedContent.Course`'s
  entire public API is `getId()`, `getName()`, `remove()`, and
  `toIntent()`. There's no way for a third-party app to read a course's
  actual coordinates; the closest a Course gets to being "usable" here is
  identifying it by name, or handing off entirely to Garmin's own native
  course/navigation screen via `toIntent()` (which exits this app). GPX
  import itself still works exactly as normal Garmin functionality (plan
  a route in Garmin Connect, sync it to the device as a Course) — it's
  specifically *drawing that course inside this app's own map screen*
  that isn't possible.

  **Known risk**: Garmin's own bug tracker has reports of
  `MapView`/`MapTrackView` simply not rendering on some devices/firmware,
  independent of app code — if the map comes up as a flat color with
  nothing on it, try opening the device's native Map screen once first
  (lets it cache map tiles for the area) before launching this app.
- **`tools/fit_to_json.py`** — a Python script you run afterwards on a
  computer to parse the ride's `.FIT` file and produce a `.json` file with
  the GPS track and the three roughness averages, ready to move to your
  iPhone (AirDrop, Files, email, etc.).

## Building and installing

1. Install VS Code + the [Monkey C extension](https://developer.garmin.com/connect-iq/monkey-c/),
   and use its guided setup until "Monkey C: Verify Installation" reports
   success.
2. Open this repo folder as the VS Code workspace root (it has
   `manifest.xml` and `monkey.jungle` at the top level).
3. Command Palette → **"Monkey C: Generate a Developer Key"** if you don't
   already have one — save it **outside** the repo (a previous key got
   accidentally committed and then deleted by a `git pull`; keeping it
   outside the repo means git can never touch it).
4. Command Palette → **"Monkey C: Set Active Device"** → **edge1030plus**.
5. Build: **F5**, or Command Palette → **"Monkey C: Build Current Project"**.
6. Sideload: connect the Edge 1030 Plus over USB, copy the built `.prg`
   from `bin/` into `GARMIN/APPS/` on the device, then eject.
7. **Remove the old data field builds** if you sideloaded any of the
   `roughness-1min` / `roughness-5min` / `roughness-trip` data fields from
   the earlier design — they can't work and should be deleted from
   `GARMIN/APPS/` (and removed from any field slots they were added to).
8. On the device, find **DS2.0 Road Quality Index** in your installed apps (not in the
   data field picker — it's a regular app) and launch it.

The manifest requests `Sensor` (accelerometer), `Fit` (creating an
`ActivityRecording` session), `FitContributor` (writing the three
developer fields), and `Positioning` (GPS-derived speed/distance/map
track) permissions, and targets `minSdkVersion 3.3.0`. The
`type="watch-app"` value and the permission names were verified against
real, current Garmin-generated manifests before use, since an earlier
guess (`type="dataField"`, camelCase) turned out to be wrong.

## Recording a ride

1. Launch **DS2.0 Road Quality Index** on the device.
2. Tap the screen to start recording. The screen shows "RECORDING" and the
   three live roughness values.
3. Ride.
4. Tap the screen again to stop and save the activity.

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
  "generated_at": "2026-08-09T14:52:59+00:00",
  "record_count": 1830,
  "roughness_fields_present": ["roughness_1min_g", "roughness_5min_g", "roughness_trip_g"],
  "road_quality": [
    { "timestamp": "2026-08-09T14:52:37+00:00", "epoch": 1786200757.0,
      "lat": 50.85, "lon": 4.35, "speed_mps": 6.1,
      "roughness_1min_g": 0.11, "roughness_5min_g": 0.09, "roughness_trip_g": 0.10 },
    ...
  ]
}
```

If `roughness_fields_present` is empty, the ride wasn't recorded with this
app (e.g. it's a normal Ride activity FIT file).

## Known caveats

- The roughness score is derived from total acceleration magnitude, not a
  calibrated "vertical" axis — this avoids needing to know the device's
  exact mount angle on the handlebars, since a static 1g reading has the
  same magnitude regardless of orientation.
- The accelerometer's live sample rate/callback cadence is fixed by the
  hardware/firmware; there's no Connect IQ API to request a specific rate.
- Recording with this app replaces your normal Ride activity profile for
  that ride — you won't see your usual power/HR/map screens while it's
  recording, only the DS2.0 Road Quality Index screen.
- This app's core recording (session, accelerometer sampling, the three
  rolling averages) has been built and run successfully on real Edge 1030
  Plus hardware. The history graph, the 2x2 stats grid, and the map
  screen are newer and haven't been tested on-device yet — build and try
  each before trusting it for a real ride.
- The map screen is the riskiest piece here (see above) — it's the first
  feature in this app built against a Garmin API with known, documented
  reliability issues on real hardware, rather than just an API we guessed
  wrong about and could fix once we saw the error.
