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

        dc.drawText(w / 2, h * 0.10, Gfx.FONT_XTINY, "Road Roughness (5 min)", Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.26, Gfx.FONT_XTINY, "Latest", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.48, Gfx.FONT_NUMBER_MEDIUM, lastText, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.64, Gfx.FONT_XTINY, "Trip avg", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.82, Gfx.FONT_TINY, avgText + " g", Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.95, Gfx.FONT_XTINY, getLastUpdatedText(), Gfx.TEXT_JUSTIFY_CENTER);
    }

}
