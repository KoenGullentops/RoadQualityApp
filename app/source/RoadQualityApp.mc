using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class RoadQualityApp extends App.AppBase {

    hidden var recorder as RoadQualityRecorder;
    hidden var calibrator as RoadQualityCalibrator?;

    function initialize() {
        AppBase.initialize();
        recorder = new RoadQualityRecorder();
        calibrator = null;
    }

    function onStart(state) {
    }

    function onStop(state) {
        if (recorder.isRecording()) {
            recorder.stopAndSave();
        }
        // If the app is exited mid-capture (sensor listener still
        // registered), cancel() unregisters it - otherwise it'd be left
        // dangling on app teardown. Harmless to call even if calibration
        // already finished or was never started.
        if (calibrator != null) {
            calibrator.cancel();
        }
    }

    // Every launch starts with a calibration screen (lift the front wheel
    // and drop it) rather than the main screen directly - mount angle and
    // position can shift between rides, and the whole point is measuring
    // this specific mount right now. RoadQualityCalibrationDelegate hands
    // off to the main view once the user accepts a result.
    function getInitialView() {
        calibrator = new RoadQualityCalibrator();
        var view = new RoadQualityCalibrationView(calibrator);
        var delegate = new RoadQualityCalibrationDelegate(calibrator, recorder);
        return [ view, delegate ];
    }

}
