using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Position as Position;
using Toybox.System as Sys;
using Toybox.PersistedContent as PersistedContent;
using Toybox.Lang as Lang;

// Real onboard-cartography map (Toybox.WatchUi.MapView). If a Course is
// loaded on the device (planned in Garmin Connect - which accepts GPX -
// and synced over, same as any other Garmin navigation course), it's
// drawn as the route to follow, with a marker for your live position.
// Otherwise falls back to drawing your own GPS breadcrumb trail so far.
//
// Known to be less reliable than the rest of this app's UI - Garmin's
// own bug tracker has reports of MapView/MapTrackView simply not
// rendering on some devices/firmware, independent of app code. The
// course-reading API in particular (readCoordinates/getCoordinateCount)
// is the least-verified piece of this whole app - if it errors, the
// message will show on the main screen's status line and that's the
// most useful next clue.
class RoadQualityMapView extends Ui.MapView {

    hidden var recorder as RoadQualityRecorder;
    hidden var lastDrawnCount as Lang.Number;
    hidden var hasCourse as Lang.Boolean;

    function initialize(recorder as RoadQualityRecorder) {
        MapView.initialize();
        self.recorder = recorder;
        lastDrawnCount = -1;
        hasCourse = false;

        // BROWSE renders full cartography (roads/terrain); PREVIEW is a
        // simplified/schematic mode - likely why the map came up as a
        // flat blue background with nothing on it.
        setMapMode(Ui.MAP_MODE_BROWSE);

        var settings = Sys.getDeviceSettings();
        setScreenVisibleArea(0, 0, settings.screenWidth, settings.screenHeight);

        // Placeholder bounding box until we have real data to size it
        // from - required at construction time, replaced below.
        setMapVisibleArea(
            new Position.Location({ :latitude => 0.01, :longitude => -0.01, :format => :degrees }),
            new Position.Location({ :latitude => -0.01, :longitude => 0.01, :format => :degrees })
        );

        hasCourse = loadCourse();
    }

    // Tries to load the first course found on the device and draw it as
    // the route to follow. Returns false (not an error - just "no course
    // loaded") if there isn't one; sets mapError only for a genuine,
    // unexpected failure while a course was actually found.
    hidden function loadCourse() as Lang.Boolean {
        try {
            var iterator = PersistedContent.getCourses();
            if (iterator == null) {
                return false;
            }

            var course = iterator.next();
            if (course == null) {
                return false;
            }

            var coordCount = course.getCoordinateCount();
            if (coordCount == null || coordCount < 2) {
                return false;
            }

            var coords = course.readCoordinates(0, coordCount);
            if (coords == null || coords.size() < 2) {
                return false;
            }

            var polyline = new Ui.MapPolyline();
            polyline.setColor(Gfx.COLOR_BLUE);
            polyline.setWidth(3);

            var first = coords[0].toDegrees();
            var minLat = first[0];
            var maxLat = first[0];
            var minLon = first[1];
            var maxLon = first[1];

            for (var i = 0; i < coords.size(); i += 1) {
                polyline.addLocation(coords[i]);

                var degrees = coords[i].toDegrees();
                if (degrees[0] < minLat) { minLat = degrees[0]; }
                if (degrees[0] > maxLat) { maxLat = degrees[0]; }
                if (degrees[1] < minLon) { minLon = degrees[1]; }
                if (degrees[1] > maxLon) { maxLon = degrees[1]; }
            }

            setPolyline(polyline);

            var latPad = ((maxLat - minLat) * 0.1d) + 0.0005d;
            var lonPad = ((maxLon - minLon) * 0.1d) + 0.0005d;
            setMapVisibleArea(
                new Position.Location({ :latitude => maxLat + latPad, :longitude => minLon - lonPad, :format => :degrees }),
                new Position.Location({ :latitude => minLat - latPad, :longitude => maxLon + lonPad, :format => :degrees })
            );

            return true;
        } catch (ex instanceof Lang.Exception) {
            recorder.setMapError("Course: " + ex.getErrorMessage());
            return false;
        }
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var count = recorder.getGpsCount();
        if (count >= 1 && count != lastDrawnCount) {
            if (hasCourse) {
                updateLiveMarker(count);
            } else if (count >= 2) {
                updateBreadcrumbPolyline(count);
            }
            lastDrawnCount = count;
        }
        MapView.onUpdate(dc);
    }

    // With a course loaded, show current position as a marker on top of
    // it rather than a second overlapping polyline.
    hidden function updateLiveMarker(count as Lang.Number) as Void {
        var lats = recorder.getGpsLat();
        var lons = recorder.getGpsLon();

        var marker = new Ui.MapMarker(new Position.Location({
            :latitude => lats[count - 1],
            :longitude => lons[count - 1],
            :format => :degrees
        }));
        setMapMarker(marker);
    }

    // No course loaded: fall back to drawing the trip's own GPS
    // breadcrumb trail, same as before.
    hidden function updateBreadcrumbPolyline(count as Lang.Number) as Void {
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

        var latPad = ((maxLat - minLat) * 0.1d) + 0.0005d;
        var lonPad = ((maxLon - minLon) * 0.1d) + 0.0005d;
        setMapVisibleArea(
            new Position.Location({ :latitude => maxLat + latPad, :longitude => minLon - lonPad, :format => :degrees }),
            new Position.Location({ :latitude => minLat - latPad, :longitude => maxLon + lonPad, :format => :degrees })
        );
    }

}
