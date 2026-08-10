using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Position as Position;
using Toybox.System as Sys;
using Toybox.Math as Math;
using Toybox.Lang as Lang;

// Real onboard-cartography map (Toybox.WatchUi.MapView), with the ride's
// GPS breadcrumb trail drawn on top, colored by roughness (green/smooth
// through yellow to red/rough - same gradient and auto-scaled min/max as
// the docs/ web viewer). A pre-planned Course cannot be drawn here -
// PersistedContent.Course's public API (confirmed against the local SDK
// docs) only exposes getId()/getName()/remove()/toIntent(), no way to
// read a course's actual coordinates from a third-party app.
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

    hidden function updatePolyline(count as Lang.Number) as Void {
        var lats = recorder.getGpsLat();
        var lons = recorder.getGpsLon();
        var roughness = recorder.getGpsRoughness();

        var minLat = lats[0];
        var maxLat = lats[0];
        var minLon = lons[0];
        var maxLon = lons[0];
        var minRoughness = roughness[0];
        var maxRoughness = roughness[0];

        for (var i = 1; i < count; i += 1) {
            if (lats[i] < minLat) { minLat = lats[i]; }
            if (lats[i] > maxLat) { maxLat = lats[i]; }
            if (lons[i] < minLon) { minLon = lons[i]; }
            if (lons[i] > maxLon) { maxLon = lons[i]; }
            if (roughness[i] < minRoughness) { minRoughness = roughness[i]; }
            if (roughness[i] > maxRoughness) { maxRoughness = roughness[i]; }
        }

        clear();

        for (var i = 1; i < count; i += 1) {
            var segment = new Ui.MapPolyline();
            var avgValue = (roughness[i - 1] + roughness[i]) / 2.0;
            segment.setColor(roughnessColor(avgValue, minRoughness, maxRoughness));
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

    // Same green (smooth) -> yellow -> red (rough) gradient as the docs/
    // web viewer's roughnessColor(), scaled to this trip's min/max so far.
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
        return Gfx.createColor(255, r, g, 0);
    }

}
