# DS2.0 Road Roughness Map (web viewer)

A static, client-side web app that renders a ride's route on a map,
colored by road-surface roughness — green (smooth) through yellow to red
(rough). No backend: everything runs in your browser, using
[Leaflet](https://leafletjs.com/) with OpenStreetMap tiles.

## Using it

1. Convert a `.FIT` file recorded with either DS2.0 Road Quality Index app
   into JSON, same as always:
   ```
   pip install -r ../tools/requirements.txt
   python3 ../tools/fit_to_json.py ride.fit ride.json
   ```
2. Open this page (locally via `index.html`, or the published GitHub
   Pages URL — see below) and drop `ride.json` onto it, or click to
   choose the file.
3. The route draws automatically, colored by whichever roughness metric
   the file has (if more than one is present — e.g. `app/`'s 1 min / 5
   min / trip averages — pick from the dropdown in the header).

Nothing is uploaded anywhere; the file is read entirely in your browser
via the File API.

## Hosting on GitHub Pages

This lives in `docs/` specifically so GitHub Pages can serve it with a
one-time settings change, no build step or extra branch needed:

1. On GitHub: **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **Deploy from a
   branch**.
3. **Branch**: pick this branch, **Folder**: `/docs`. Save.
4. GitHub will publish it at `https://<your-username>.github.io/<repo>/`
   within a minute or two.

Note: GitHub Pages is free for public repositories. If this repo is
private, Pages requires a paid GitHub plan (Pro/Team/Enterprise) — or you
can just open `index.html` directly from disk, or host the `docs/` folder
on any other static host (Netlify, Vercel, etc.), since it has zero
server-side dependencies.

## Known caveats

- Data field snapshots (`roughness_snapshot_g`/`roughness_trip_avg_g`,
  from `datafield/`, updated roughly every 5 minutes) are forward-filled
  between samples so the whole route still gets colored — meaning
  stretches of road between snapshots show the *previous* reading, not
  necessarily what that specific stretch was actually like.
- The color scale is normalized to the min/max roughness within the
  loaded ride, not a fixed absolute scale — so "red" on one ride and
  "red" on another don't necessarily mean the same actual roughness
  value. The legend always shows the actual g values for the loaded ride.
- Leaflet is vendored into `vendor/leaflet/` rather than loaded from a
  CDN, so the page has no external script dependency and works from a
  plain `file://` open with no network access at all except for the map
  tile images themselves (those still come from OpenStreetMap's tile
  servers, since redistributing map imagery isn't practical).
