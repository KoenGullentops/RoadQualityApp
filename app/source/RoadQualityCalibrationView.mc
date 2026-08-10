using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;

class RoadQualityCalibrationView extends Ui.View {

    hidden var calibrator as RoadQualityCalibrator;

    function initialize(calibrator as RoadQualityCalibrator) {
        View.initialize();
        self.calibrator = calibrator;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.06, Gfx.FONT_TINY, "Calibration", Gfx.TEXT_JUSTIFY_CENTER);

        var state = calibrator.getState();
        if (state == RoadQualityCalibrator.STATE_IDLE) {
            drawLines(dc, w, h * 0.20, [
                "Mount the device on the",
                "stem as normal. Lift the",
                "front wheel ~10cm and",
                "drop it, to measure how",
                "your mount responds to a bump."
            ]);
            dc.drawText(w / 2, h * 0.85, Gfx.FONT_TINY, "Tap to start", Gfx.TEXT_JUSTIFY_CENTER);
        } else if (state == RoadQualityCalibrator.STATE_BASELINE) {
            dc.drawText(w / 2, h * 0.40, Gfx.FONT_MEDIUM, "Hold still...", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.55, Gfx.FONT_TINY, "measuring baseline", Gfx.TEXT_JUSTIFY_CENTER);
        } else if (state == RoadQualityCalibrator.STATE_CAPTURING) {
            dc.drawText(w / 2, h * 0.35, Gfx.FONT_MEDIUM, "Lift & drop now!", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.50, Gfx.FONT_TINY, "front wheel ~10cm", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.65, Gfx.FONT_NUMBER_MEDIUM,
                calibrator.getPhaseSecondsRemaining().format("%d"), Gfx.TEXT_JUSTIFY_CENTER);
        } else if (state == RoadQualityCalibrator.STATE_DONE) {
            drawResult(dc, w, h);
        }
    }

    hidden function drawResult(dc as Gfx.Dc, w as Lang.Number, h as Lang.Number) as Void {
        var confident = calibrator.isConfident();

        dc.drawText(w / 2, h * 0.20, Gfx.FONT_TINY, "Detected bump axis", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.32, Gfx.FONT_NUMBER_MEDIUM, calibrator.getAxisName(), Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.50, Gfx.FONT_TINY, "Peak response", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.62, Gfx.FONT_MEDIUM,
            calibrator.getPeakDeviation().format("%.2f") + " g", Gfx.TEXT_JUSTIFY_CENTER);

        if (!confident) {
            dc.setColor(Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
            drawLines(dc, w, h * 0.72, [
                "That barely moved - did it",
                "actually drop? Swipe to retry."
            ]);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }

        dc.drawText(w / 2, h * 0.90, Gfx.FONT_XTINY, "Tap: accept    Swipe: retry", Gfx.TEXT_JUSTIFY_CENTER);
    }

    // Lang.String has no split()/word-wrap helper in this SDK, so
    // multi-line prompts are just passed in pre-broken rather than
    // wrapped dynamically.
    hidden function drawLines(dc as Gfx.Dc, w as Lang.Number, startY as Lang.Numeric, lines as Lang.Array<Lang.String>) as Void {
        var lineHeight = dc.getFontHeight(Gfx.FONT_TINY) * 1.1;
        var y = startY;
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(w / 2, y, Gfx.FONT_TINY, lines[i], Gfx.TEXT_JUSTIFY_CENTER);
            y += lineHeight;
        }
    }

}
