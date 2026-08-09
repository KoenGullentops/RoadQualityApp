using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.FitContributor as Fit;
using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;

// Displays the latest roughness snapshot the background service
// computed (see RoadQualityServiceDelegate), refreshed every 5 minutes,
// plus a running average of every snapshot taken so far this trip.
// Never touches the accelerometer itself - Data Fields can't.
class RoadQualityField extends Ui.DataField {

    hidden var snapshotField as Fit.Field;
    hidden var tripAvgField as Fit.Field;

    function initialize() {
        DataField.initialize();

        snapshotField = createField(
            "roughness_snapshot_g", 0, Fit.DATA_TYPE_FLOAT,
            { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
        );
        tripAvgField = createField(
            "roughness_trip_avg_g", 1, Fit.DATA_TYPE_FLOAT,
            { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
        );
    }

    // The background service only ever adds to tripSum/tripCount - this
    // is the one place that clears them, so a trip's average doesn't
    // bleed into the next ride.
    function onTimerReset() as Void {
        Storage.deleteValue("tripSum");
        Storage.deleteValue("tripCount");
        Storage.deleteValue("lastRoughness");
        Storage.deleteValue("lastUpdatedAt");
        Storage.deleteValue("history");
    }

    function compute(info) {
        var last = Storage.getValue("lastRoughness");
        var value = 0.0;
        if (last != null) {
            value = last as Lang.Float;
        }

        var avg = getTripAverage();

        snapshotField.setData(value);
        tripAvgField.setData(avg);

        return value;
    }

    hidden function getTripAverage() as Lang.Float {
        var tripSum = Storage.getValue("tripSum");
        var tripCount = Storage.getValue("tripCount");
        if (tripSum == null || tripCount == null || (tripCount as Lang.Number) == 0) {
            return 0.0;
        }
        return (tripSum as Lang.Float) / (tripCount as Lang.Number);
    }

    hidden function getLastUpdatedText() as Lang.String {
        var ts = Storage.getValue("lastUpdatedAt");
        if (ts == null) {
            return "LAST UPDATED --:--";
        }
        var moment = new Time.Moment(ts as Lang.Number);
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return "LAST UPDATED " + info.hour.format("%02d") + ":" + info.min.format("%02d");
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var last = Storage.getValue("lastRoughness");
        var lastText = last == null ? "--" : (last as Lang.Float).format("%.2f");
        var avgText = getTripAverage().format("%.2f");

        dc.drawText(w / 2, h * 0.07, Gfx.FONT_XTINY, "Road Roughness", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.20, Gfx.FONT_TINY,
            "Latest " + lastText + "  Avg " + avgText + " g", Gfx.TEXT_JUSTIFY_CENTER);

        var graphX = (w * 0.06).toNumber();
        var graphY = (h * 0.30).toNumber();
        var graphW = (w * 0.88).toNumber();
        var graphH = (h * 0.55).toNumber();
        drawGraph(dc, graphX, graphY, graphW, graphH);

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.92, Gfx.FONT_XTINY, getLastUpdatedText(), Gfx.TEXT_JUSTIFY_CENTER);
    }

    // Trip-so-far roughness trace: oldest snapshot at the left edge,
    // most recent at the right, y-axis auto-scaled to the highest
    // snapshot seen so far this trip. Colors chosen for contrast against
    // the field's white background.
    hidden function drawGraph(dc as Gfx.Dc, x as Lang.Number, y as Lang.Number, w as Lang.Number, h as Lang.Number) as Void {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, w, h);

        var stored = Storage.getValue("history");
        if (stored == null) {
            dc.drawText(x + w / 2, y + h / 2, Gfx.FONT_XTINY, "No data yet", Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var points = stored as Lang.Array<Lang.Float>;
        var count = points.size();
        if (count < 2) {
            dc.drawText(x + w / 2, y + h / 2, Gfx.FONT_XTINY, "No data yet", Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var maxValue = 0.05;
        for (var i = 0; i < count; i += 1) {
            if (points[i] > maxValue) { maxValue = points[i]; }
        }

        dc.setColor(Gfx.COLOR_DK_BLUE, Gfx.COLOR_TRANSPARENT);

        var prevX = x;
        var prevY = y + h - ((points[0] / maxValue) * h).toNumber();

        for (var i = 1; i < count; i += 1) {
            var px = x + (i * w) / (count - 1);
            var py = y + h - ((points[i] / maxValue) * h).toNumber();
            dc.drawLine(prevX, prevY, px, py);
            prevX = px;
            prevY = py;
        }
    }

}
