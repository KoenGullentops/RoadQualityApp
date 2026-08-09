using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Position as Position;
using Toybox.System as Sys;
using Toybox.Lang as Lang;

// Real onboard-cartography map (Toybox.WatchUi.MapView), with the ride's
// GPS breadcrumb trail drawn on top. A pre-planned Course cannot be drawn
// here - PersistedContent.Course's public API (confirmed against the
// local SDK docs) only exposes getId()/getName()/remove()/toIntent(), no
// way to read a course's actual coordinates from a third-party app.
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

        var polyline = new Ui.MapPolyline();
        polyline.setColor(Gfx.COLOR_RED);
        polyline.setWidth(3);

        var minLat = lats[0];
        var maxLat = lats[0];
        var minLon = lons[0];
        var maxLon = lons[0];

        for (var i = 0; i < count; i += 1) {
            polyline.addLocation(new Position.Location({
                :latitude => lats[i],
                :longitude => lons[i],
                :format => :degrees
            }));

            if (lats[i] < minLat) { minLat = lats[i]; }
            if (lats[i] > maxLat) { maxLat = lats[i]; }
            if (lons[i] < minLon) { minLon = lons[i]; }
            if (lons[i] > maxLon) { maxLon = lons[i]; }
        }

        setPolyline(polyline);

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

}
