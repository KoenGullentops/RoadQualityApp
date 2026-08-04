using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer as Timer;

class RoadQualityView extends Ui.View {

    hidden var recorder;
    hidden var refreshTimer;

    function initialize(recorder) {
        View.initialize();
        self.recorder = recorder;
        refreshTimer = new Timer.Timer();
    }

    function onLayout(dc) {
    }

    function onShow() {
        // Redraw once a second while visible so the elapsed time / sample
        // count keep moving during a recording.
        refreshTimer.start(method(:onRefresh), 1000, true);
    }

    function onHide() {
        refreshTimer.stop();
    }

    function onRefresh() {
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.16, Gfx.FONT_MEDIUM, "Road Quality", Gfx.TEXT_JUSTIFY_CENTER);

        var status = recorder.isRecording() ? "RECORDING" : "STOPPED";
        dc.drawText(w / 2, h * 0.38, Gfx.FONT_LARGE, status, Gfx.TEXT_JUSTIFY_CENTER);

        if (recorder.isRecording()) {
            dc.drawText(w / 2, h * 0.58, Gfx.FONT_NUMBER_MEDIUM, recorder.getElapsedString(), Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.76, Gfx.FONT_TINY, recorder.getSampleCountString(), Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(w / 2, h * 0.58, Gfx.FONT_TINY, "Press START to begin", Gfx.TEXT_JUSTIFY_CENTER);
        }

        dc.drawText(w / 2, h * 0.92, Gfx.FONT_XTINY, recorder.getStatusLine(), Gfx.TEXT_JUSTIFY_CENTER);
    }

}
