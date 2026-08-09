using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Position as Position;
using Toybox.Lang as Lang;

// Real onboard-cartography map (Toybox.WatchUi.MapView), with the ride's
// GPS breadcrumb trail drawn on top. Known to be less reliable than the
// rest of this app's UI - Garmin's own bug tracker has reports of
// MapView/MapTrackView simply not rendering on some devices/firmware,
// independent of the app's own code - so if the map screen shows nothing,
// that's a plausible platform issue, not necessarily a bug here.
class RoadQualityMapView extends Ui.MapView {

    hidden var recorder as RoadQualityRecorder;
    hidden var lastDrawnCount as Lang.Number;

    function initialize(recorder as RoadQualityRecorder) {
        MapView.initialize();
        self.recorder = recorder;
        lastDrawnCount = -1;
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

        for (var i = 0; i < count; i += 1) {
            polyline.addLocation(new Position.Location({
                :latitude => lats[i],
                :longitude => lons[i],
                :format => :degrees
            }));
        }

        setPolyline(polyline);
    }

}
