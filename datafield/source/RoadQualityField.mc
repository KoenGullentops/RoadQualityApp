using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.FitContributor as Fit;
using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;

// Displays the latest roughness snapshot the background service
// computed (see RoadQualityServiceDelegate), refreshed every 5 minutes.
// Never touches the accelerometer itself - Data Fields can't.
class RoadQualityField extends Ui.DataField {

    hidden var snapshotField as Fit.Field;

    function initialize() {
        DataField.initialize();

        snapshotField = createField(
            "roughness_snapshot_g", 0, Fit.DATA_TYPE_FLOAT,
            { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
        );
    }

    function compute(info) {
        var last = Storage.getValue("lastRoughness");
        var value = 0.0;
        if (last != null) {
            value = last as Lang.Float;
        }

        snapshotField.setData(value);
        return value;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var last = Storage.getValue("lastRoughness");
        var text = last == null ? "--" : (last as Lang.Float).format("%.2f");

        dc.drawText(w / 2, h * 0.18, Gfx.FONT_XTINY, "Road Roughness", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.55, Gfx.FONT_NUMBER_MEDIUM, text, Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.85, Gfx.FONT_XTINY, "g (updates every 5 min)", Gfx.TEXT_JUSTIFY_CENTER);
    }

}
