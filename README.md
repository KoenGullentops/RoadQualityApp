# DS2.0 Road Quality Index (Garmin Edge 1030 Plus)

Two separate Connect IQ apps for measuring road-surface roughness from the
Edge 1030 Plus's accelerometer, for two different use cases:

| Project | What it is | Update cadence | Use case |
|---|---|---|---|
| `app/` | Standalone watch app, owns its own recording session | Continuous (1 Hz) | Dedicated "road quality" rides where you don't need your normal ride screens |
| `datafield/` | A tile you add to your normal Ride activity screen | ~Every 5 minutes | Everyday rides where you still want power/HR/maps/etc., plus a lightweight roughness reading |
| `docs/` | Static web app (GitHub Pages) | — | View a ride's route on a map, colored by roughness, from the JSON either app produces |

## Why two apps, and why the data field only updates every 5 minutes

**Data Fields cannot read accelerometer data continuously, on Edge devices,
by any method.** Confirmed directly from an on-device crash log:

```
Error: Permission Required
Details: "Symbol 'registerSensorDataListener' not available to 'Data Field'"
```

and independently corroborated by other developers' reports that the older
polling API (`Sensor.getInfo()`) crashes from a Data Field too, and that
`SensorHistory` (which would have been a workaround, since it logs sensor
data at the OS level regardless of which app is in the foreground) doesn't
exist on Edge devices at all.

The only way to read the accelerometer *continuously* is a standalone app
that owns its own `Toybox.ActivityRecording` session — that's `app/`. Its
trade-off: you start it instead of your normal Ride profile, so you lose
your other usual fields while it's recording.

`datafield/` gets around that trade-off a different way. Its own
`compute()`/`onUpdate()` never touch the accelerometer — instead, the Data
Field registers a **background service** (`Toybox.Background`), which
`Toybox.Sensor`'s docs list as a *separate* supported runtime context from
"Data Field". Every 5 minutes (the minimum interval Connect IQ allows for
a scheduled background wake — confirmed against the local SDK docs, which
list exactly six background trigger types, none of them continuous or
sensor-event-driven), the background service briefly samples the
accelerometer, computes one roughness reading, and stores it; the Data
Field's `compute()` just displays whatever was last stored. This is the
same well-known pattern as a "rain radar" data field (periodic background
fetch, display the cached result) — here the periodic fetch is a short
accelerometer sample instead of a web request.

Trade-off: you get a snapshot every ~5 minutes, not a rolling average —
there's no way to make it more frequent (5 minutes is Connect IQ's hard
floor for background wakes) or continuous (a Data Field's own foreground
code still can't touch the accelerometer at all).

## `app/` — standalone continuous app

- **`source/RoadQualityRecorder.mc`** — owns the FIT recording session,
  reads live accelerometer via `Sensor.registerSensorDataListener`, and
  once per second (via a 1 Hz timer) turns the accumulated samples into
  an instantaneous roughness value: the RMS of `|acceleration| - 1g` (how
  far the total acceleration deviates from gravity). That value feeds
  three running averages:
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

## `datafield/` — 5-minute background snapshot tile

- **`source/RoadQualityFieldApp.mc`** — registers the 5-minute background
  wake (`Background.registerForTemporalEvent`) and returns the field as
  the initial view. Marked `(:background)`, as required for any code
  reachable from the background service.
- **`source/RoadQualityServiceDelegate.mc`** — the background service.
  Wakes every 5 minutes, registers a *short* accelerometer listener
  (`:period => 4`, the max Connect IQ allows per batch), computes one RMS
  roughness reading the same way `app/` does, and exits — well inside the
  30-second budget Connect IQ gives a background process. Stores that
  reading as the latest snapshot, and folds it into a running trip
  sum/count for a trip-wide average, both via `Application.Storage`.
- **`source/RoadQualityField.mc`** — the actual data field. Reads the
  last stored snapshot and the running trip average each second, displays
  both, and writes both into the FIT file as developer fields
  (`roughness_snapshot_g`, `roughness_trip_avg_g`) via
  `Toybox.FitContributor`. Never calls any `Sensor` API itself.
  `onTimerReset()` (fired only when a ride genuinely ends, not on
  pause/resume — confirmed via the local SDK docs, which document
  `onTimerPause`/`onTimerResume` as separate callbacks from `onTimerStart`)
  clears the trip sum/count so the average doesn't carry over into the
  next ride. White background with black text (rather than the reverse),
  and a small "LAST UPDATED HH:MM" line showing when the background
  service last actually ran.

  The background service also appends each snapshot to a persisted
  history array (`Application.Storage` can hold a `Lang.Array`, capped at
  100 points — over 8 hours of riding at one point per 5 minutes, oldest
  dropped past that via `Array.slice()`), and the field draws it as a
  small line graph below the numbers, same auto-scaling approach as
  `app/`'s graph. Also cleared on `onTimerReset()`.

This hasn't been tested on-device yet — the API shapes and background
constraints are all verified against the local Connect IQ SDK docs, but
the actual on-device timing (does the background wake reliably fire while
another activity profile is showing this tile? does 4 seconds of
accelerometer sampling produce a representative reading?) is unverified
until a real test.

## Building and installing

Each of `app/` and `datafield/` is a separate, independent Connect IQ
project (its own `manifest.xml` + `monkey.jungle`). Build and install
whichever one(s) you want, the same way each time:

1. Install VS Code + the [Monkey C extension](https://developer.garmin.com/connect-iq/monkey-c/),
   and use its guided setup until "Monkey C: Verify Installation" reports
   success.
2. Open `app/` **or** `datafield/` (not the repo root) as the VS Code
   workspace folder.
3. Command Palette → **"Monkey C: Generate a Developer Key"** if you don't
   already have one — save it **outside** the repo (a previous key got
   accidentally committed and then deleted by a `git pull`; keeping it
   outside the repo means git can never touch it). The same key signs
   both projects.
4. Command Palette → **"Monkey C: Set Active Device"** → **edge1030plus**.
5. Build: **F5**, or Command Palette → **"Monkey C: Build Current Project"**.
6. Sideload: connect the Edge 1030 Plus over USB, copy the built `.prg`
   from `bin/` into `GARMIN/APPS/` on the device, then eject.
7. **Remove the old `roughness-1min`/`roughness-5min`/`roughness-trip`
   data field builds** if you still have them sideloaded from an earlier,
   abandoned design — they can't work and should be deleted from
   `GARMIN/APPS/` (and removed from any field slots they were added to).
8. Repeat for the other project if you want both installed.

`app/manifest.xml` requests `Sensor` (accelerometer), `Fit` (creating an
`ActivityRecording` session), `FitContributor` (writing developer fields),
and `Positioning` (GPS-derived speed/distance/map track). Note that having
the `Positioning` permission declared is not enough by itself — the GPS
receiver only actually turns on because `RoadQualityRecorder.start()`
explicitly calls `Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, ...)`.
Creating and starting the `ActivityRecording.Session` does not enable it
implicitly; early builds of this app omitted that call, so recordings had
no position/speed/distance at all even during genuine outdoor testing
with a GPS fix available — confirmed against the local SDK docs
("Controlling the FIT file recording requires a few steps: enable the
sensors to be recorded...").
`datafield/manifest.xml` requests `Sensor`, `Background`, and
`FitContributor`. Both target `minSdkVersion 3.3.0`. The `type` values
(`watch-app` for `app/`, `datafield` for `datafield/`) and permission
names were verified against real, current Garmin-generated manifests
before use, since an earlier guess (`type="dataField"`, camelCase) turned
out to be wrong.

## Using `app/` (standalone, continuous)

1. Launch **DS2.0 Road Quality Index** on the device (a regular app, not
   in the data field picker).
2. Tap the screen to start recording. The screen shows "RECORDING" and
   the three live roughness values.
3. Ride.
4. Tap the screen again to stop and save the activity.

## Using `datafield/` (tile, 5-min snapshots)

1. Start your normal Ride activity as usual.
2. On the field layout editor, add **Road Roughness** to an empty field
   slot — it appears in the normal data field picker like power or speed.
3. Ride normally. The tile shows `--` until the first background sample
   arrives (up to 5 minutes in), then updates roughly every 5 minutes.

## Getting the FIT file and converting it

Works the same regardless of which app recorded the ride:

1. Connect the Edge 1030 Plus by USB (or use Garmin Express) and copy the
   activity file out of `GARMIN/ACTIVITY/`.
2. Convert it:
   ```
   pip install -r tools/requirements.txt
   python3 tools/fit_to_json.py path/to/ride.fit ride.json
   ```
3. Move `ride.json` to your iPhone (AirDrop, Files, email, etc.), or open
   it with **`docs/index.html`** — see [`docs/README.md`](docs/README.md)
   — to see the route on a map, colored by roughness.

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

A ride recorded with `datafield/` instead will have `roughness_snapshot_g`
(only on the roughly-every-5-minutes records where a fresh background
sample landed; `null` elsewhere) and `roughness_trip_avg_g` (present on
every record once the first snapshot has landed, since it's just written
alongside the snapshot each second — same value repeated between
snapshots) rather than the other three fields. If `roughness_fields_present`
is empty, the ride wasn't recorded with either app.

## Known caveats

- The roughness score is derived from total acceleration magnitude, not a
  calibrated "vertical" axis — this avoids needing to know the device's
  exact mount angle on the handlebars, since a static 1g reading has the
  same magnitude regardless of orientation.
- The accelerometer's live sample rate/callback cadence is fixed by the
  hardware/firmware; there's no Connect IQ API to request a specific rate.
- `app/`'s core recording (session, accelerometer sampling, the three
  rolling averages) has been built and run successfully on real Edge 1030
  Plus hardware. Its history graph, 2x2 stats grid, and map screen are
  newer and less thoroughly tested on-device.
- `app/`'s map screen is its riskiest piece — the first feature in this
  project built against a Garmin API (`MapView`) with known, documented
  reliability issues on real hardware, rather than just an API we guessed
  wrong about and could fix once we saw the error.
- `datafield/` hasn't been tested on-device at all yet. The design is
  verified against the local SDK docs (background trigger types, Sensor's
  documented runtime contexts, `Background.exit`/`Storage` semantics) but
  real-device timing behavior is unconfirmed.
- Every `app/` ride recorded before the GPS fix above had no
  position/speed/distance at all, confirmed on real outdoor rides with a
  GPS fix available (not just no fix yet, as originally assumed) - the
  session was simply never turning the GPS receiver on. This also means
  the 2x2 stats grid's speed/distance and the map screen's breadcrumb
  trail were never actually populated in any test so far, not just
  "untested" as previously stated here. Retest all of `app/` on a real
  ride now that GPS is properly enabled.
