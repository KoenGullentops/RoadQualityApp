using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Position as Position;
using Toybox.System as Sys;
using Toybox.Math as Math;
using Toybox.Lang as Lang;

// Real onboard-cartography map (Toybox.WatchUi.MapView), with the ride's
// GPS breadcrumb trail drawn on top, colored by roughness (green/smooth
// through yellow to red/rough, scaled to the 5th-95th percentile of
// riding-only readings - same approach as the docs/ web viewer, see
// MIN_RIDING_SPEED_MPS below). Walking/stopped segments are drawn in
// gray rather than colored, since that motion isn't road-surface data
// at all. A pre-planned Course cannot be drawn here - PersistedContent.
// Course's public API (confirmed against the local SDK docs) only
// exposes getId()/getName()/remove()/toIntent(), no way to read a
// course's actual coordinates from a third-party app.
//
// MapPolyline only supports one solid color per polyline (setColor()),
// so the color-coded trail is built from many short two-point polylines,
// one per breadcrumb segment, re-added on every redraw. setPolyline() is
// documented as "Add" (not replace/set), so clear() is called first each
// time to drop the previous redraw's segments rather than accumulating
// them forever.
//
// Known to be less reliable than the rest of this app's UI - Garmin's
// own bug tracker has reports of MapView/MapTrackView simply not
// rendering on some devices/firmware, independent of app code. If the
// map comes up as a flat color with nothing on it, try opening the
// device's native Map screen once first (lets it cache tiles for the
// area) before launching this app.
class RoadQualityMapView extends Ui.MapView {

    hidden var recorder as RoadQualityRecorder;
    hidden var lastDrawnCount as Lang.Number;

    function initialize(recorder as RoadQualityRecorder) {
        MapView.initialize();
        self.recorder = recorder;
        lastDrawnCount = -1;

        // BROWSE renders full cartography (roads/terrain); PREVIEW is a
        // simplified/schematic mode.
        setMapMode(Ui.MAP_MODE_BROWSE);

        var settings = Sys.getDeviceSettings();
        setScreenVisibleArea(0, 0, settings.screenWidth, settings.screenHeight);

        // Placeholder bounding box until we have real GPS data to size it
        // from - required at construction time, updated once points exist.
        setMapVisibleArea(
            new Position.Location({ :latitude => 0.01, :longitude => -0.01, :format => :degrees }),
            new Position.Location({ :latitude => -0.01, :longitude => 0.01, :format => :degrees })
        );
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var count = recorder.getGpsCount();
        if (count >= 2 && count != lastDrawnCount) {
            updatePolyline(count);
            lastDrawnCount = count;
        }
        MapView.onUpdate(dc);
    }

    // Below this, treated as walking/stopped rather than riding - see
    // the matching constant and comment in docs/index.html for the full
    // rationale (a real ride showed walking-with-bike readings several
    // times higher than any actual pavement, badly distorting a linear
    // color scale built from every point).
    hidden const MIN_RIDING_SPEED_MPS as Lang.Float = 1.5;

    hidden function updatePolyline(count as Lang.Number) as Void {
        var lats = recorder.getGpsLat();
        var lons = recorder.getGpsLon();
        var roughness = recorder.getGpsRoughness();
        var speed = recorder.getGpsSpeed();

        var minLat = lats[0];
        var maxLat = lats[0];
        var minLon = lons[0];
        var maxLon = lons[0];

        var ridingValues = [] as Lang.Array<Lang.Float>;
        for (var i = 0; i < count; i += 1) {
            if (lats[i] < minLat) { minLat = lats[i]; }
            if (lats[i] > maxLat) { maxLat = lats[i]; }
            if (lons[i] < minLon) { minLon = lons[i]; }
            if (lons[i] > maxLon) { maxLon = lons[i]; }
            if (speed[i] >= MIN_RIDING_SPEED_MPS) {
                ridingValues.add(roughness[i]);
            }
        }

        // Percentile clamping (5th-95th) instead of raw min/max, so one
        // outlier - a single hard pothole, or a walking sample that
        // slipped past the speed check - can't stretch the whole scale
        // and wash out every other reading into flat green. Falls back
        // to plain min/max over everything if there's too little riding
        // data to get percentiles from.
        var minRoughness = 0.0;
        var maxRoughness = 0.0;
        if (ridingValues.size() >= 5) {
            insertionSort(ridingValues);
            var n = ridingValues.size();
            var p5Index = (n * 0.05).toNumber();
            var p95Index = (n * 0.95).toNumber();
            if (p95Index >= n) { p95Index = n - 1; }
            minRoughness = ridingValues[p5Index];
            maxRoughness = ridingValues[p95Index];
            if (maxRoughness <= minRoughness) {
                maxRoughness = ridingValues[n - 1];
            }
        } else {
            minRoughness = roughness[0];
            maxRoughness = roughness[0];
            for (var i = 1; i < count; i += 1) {
                if (roughness[i] < minRoughness) { minRoughness = roughness[i]; }
                if (roughness[i] > maxRoughness) { maxRoughness = roughness[i]; }
            }
        }

        clear();

        for (var i = 1; i < count; i += 1) {
            var segment = new Ui.MapPolyline();
            var bothRiding = speed[i - 1] >= MIN_RIDING_SPEED_MPS && speed[i] >= MIN_RIDING_SPEED_MPS;
            if (bothRiding) {
                var avgValue = (roughness[i - 1] + roughness[i]) / 2.0;
                segment.setColor(roughnessColor(avgValue, minRoughness, maxRoughness));
            } else {
                segment.setColor(Gfx.COLOR_DK_GRAY);
            }
            segment.setWidth(4);
            segment.addLocation([
                new Position.Location({ :latitude => lats[i - 1], :longitude => lons[i - 1], :format => :degrees }),
                new Position.Location({ :latitude => lats[i], :longitude => lons[i], :format => :degrees })
            ]);
            setPolyline(segment);
        }

        // Pad the bounding box a bit so the route isn't drawn right at
        // the screen edge, with a floor so a near-stationary trip (tiny
        // lat/lon span) still gets a sane amount of surrounding map.
        var latPad = ((maxLat - minLat) * 0.1d) + 0.0005d;
        var lonPad = ((maxLon - minLon) * 0.1d) + 0.0005d;

        setMapVisibleArea(
            new Position.Location({ :latitude => maxLat + latPad, :longitude => minLon - lonPad, :format => :degrees }),
            new Position.Location({ :latitude => minLat - latPad, :longitude => maxLon + lonPad, :format => :degrees })
        );
    }

    // Array.sort() needs API Level 5.0.0, which the Edge 1030 Plus
    // doesn't support (confirmed the same way as the createColor build
    // error above) - plain insertion sort instead, fine for the at most
    // 120 elements this ever sees.
    hidden function insertionSort(values as Lang.Array<Lang.Float>) as Void {
        for (var i = 1; i < values.size(); i += 1) {
            var key = values[i];
            var j = i - 1;
            while (j >= 0 && values[j] > key) {
                values[j + 1] = values[j];
                j -= 1;
            }
            values[j + 1] = key;
        }
    }

    // Same green (smooth) -> yellow -> red (rough) gradient as the docs/
    // web viewer's roughnessColor(), scaled to this trip's min/max so far.
    // Graphics.ColorType is just a packed 0xRRGGBB Number (confirmed from
    // the ColorValue constants, e.g. COLOR_GREEN = 0x00FF00), available
    // since API Level 1.0.0 - built directly with bit shifts instead of
    // Graphics.createColor(), which needs API Level 4.0.0 and isn't
    // supported on the Edge 1030 Plus (confirmed by an actual build
    // error: "Device 'edge1030plus' does not support API Level '4.0.0'").
    hidden function roughnessColor(value as Lang.Float, minValue as Lang.Float, maxValue as Lang.Float) as Gfx.ColorType {
        var t = 0.0;
        if (maxValue > minValue) {
            t = (value - minValue) / (maxValue - minValue);
        }
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }

        var r = 255;
        var g = 255;
        if (t < 0.5) {
            r = Math.round(255 * (t / 0.5)).toNumber();
        } else {
            g = Math.round(255 * (1 - (t - 0.5) / 0.5)).toNumber();
        }
        return (r << 16) | (g << 8);
    }

}
