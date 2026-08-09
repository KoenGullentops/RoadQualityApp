using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;

class RoadQualityView extends Ui.View {

    hidden var recorder as RoadQualityRecorder;

    function initialize(recorder as RoadQualityRecorder) {
        View.initialize();
        self.recorder = recorder;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var status = recorder.isRecording()
            ? "RECORDING - tap to stop & save"
            : "Tap to start recording";

        dc.drawText(w / 2, h * 0.08, Gfx.FONT_XTINY, "Road Quality", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.20, Gfx.FONT_XTINY, status, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.42, Gfx.FONT_TINY,
            "1 min: " + recorder.getValue1Min().format("%.2f") + " g", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.60, Gfx.FONT_TINY,
            "5 min: " + recorder.getValue5Min().format("%.2f") + " g", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.78, Gfx.FONT_TINY,
            "Trip: " + recorder.getValueTrip().format("%.2f") + " g", Gfx.TEXT_JUSTIFY_CENTER);
    }

}
