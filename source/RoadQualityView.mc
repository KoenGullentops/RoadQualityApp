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

        dc.drawText(w / 2, h * 0.04, Gfx.FONT_XTINY, "DS2.0 Road Quality Index", Gfx.TEXT_JUSTIFY_CENTER);

        var error = recorder.getLastError();
        if (error != null) {
            dc.drawText(w / 2, h * 0.18, Gfx.FONT_XTINY, "Error - tap to retry", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.30, Gfx.FONT_XTINY, error, Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var status = recorder.isRecording()
            ? "RECORDING - tap to stop & save"
            : "Tap to start recording";
        dc.drawText(w / 2, h * 0.14, Gfx.FONT_XTINY, status, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.24, Gfx.FONT_TINY,
            "1m " + recorder.getValue1Min().format("%.2f")
            + "  5m " + recorder.getValue5Min().format("%.2f")
            + "  Trip " + recorder.getValueTrip().format("%.2f") + " g",
            Gfx.TEXT_JUSTIFY_CENTER);

        var graphX = (w * 0.06).toNumber();
        var graphY = (h * 0.34).toNumber();
        var graphW = (w * 0.88).toNumber();
        var graphH = (h * 0.58).toNumber();
        drawGraph(dc, graphX, graphY, graphW, graphH);
    }

    // Draws the whole-trip roughness trace: oldest reading at the left
    // edge, most recent at the right, y-axis auto-scaled to the highest
    // reading seen so far this trip.
    hidden function drawGraph(dc as Gfx.Dc, x as Lang.Number, y as Lang.Number, w as Lang.Number, h as Lang.Number) as Void {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, w, h);

        var count = recorder.getHistoryCount();
        if (count < 2) {
            dc.drawText(x + w / 2, y + h / 2, Gfx.FONT_XTINY, "Waiting for data...", Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var history = recorder.getHistory();
        var maxValue = recorder.getHistoryMaxValue();
        if (maxValue <= 0.0) {
            maxValue = 0.01;
        }

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);

        var prevX = x;
        var prevY = y + h - ((history[0] / maxValue) * h).toNumber();

        for (var i = 1; i < count; i += 1) {
            var px = x + (i * w) / (count - 1);
            var py = y + h - ((history[i] / maxValue) * h).toNumber();
            dc.drawLine(prevX, prevY, px, py);
            prevX = px;
            prevY = py;
        }
    }

}
