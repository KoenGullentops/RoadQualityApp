using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;

class RoadQualityCalibrationDelegate extends Ui.BehaviorDelegate {

    hidden var calibrator as RoadQualityCalibrator;
    hidden var recorder as RoadQualityRecorder;

    function initialize(calibrator as RoadQualityCalibrator, recorder as RoadQualityRecorder) {
        BehaviorDelegate.initialize();
        self.calibrator = calibrator;
        self.recorder = recorder;
    }

    // Tap: start the test from idle, or accept a finished result and
    // move on to the main screen.
    function onSelect() as Lang.Boolean {
        handleTap();
        return true;
    }

    function onTap(clickEvent) as Lang.Boolean {
        handleTap();
        return true;
    }

    hidden function handleTap() as Void {
        var state = calibrator.getState();
        if (state == RoadQualityCalibrator.STATE_IDLE) {
            calibrator.start();
            Ui.requestUpdate();
        } else if (state == RoadQualityCalibrator.STATE_DONE) {
            accept();
        }
    }

    // Swipe/page button: retry a finished result. No effect mid-capture,
    // where an accidental swipe shouldn't derail the test.
    function onNextPage() as Lang.Boolean {
        if (calibrator.getState() == RoadQualityCalibrator.STATE_DONE) {
            calibrator.start();
            Ui.requestUpdate();
        }
        return true;
    }

    hidden function accept() as Void {
        recorder.setCalibration(
            calibrator.getPeakAxis(),
            calibrator.getBaseX(),
            calibrator.getBaseY(),
            calibrator.getBaseZ()
        );
        Ui.switchToView(
            new RoadQualityView(recorder),
            new RoadQualityDelegate(recorder),
            Ui.SLIDE_IMMEDIATE
        );
    }

}
