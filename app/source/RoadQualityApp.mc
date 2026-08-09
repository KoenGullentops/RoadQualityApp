using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class RoadQualityApp extends App.AppBase {

    hidden var recorder as RoadQualityRecorder;

    function initialize() {
        AppBase.initialize();
        recorder = new RoadQualityRecorder();
    }

    function onStart(state) {
    }

    function onStop(state) {
        if (recorder.isRecording()) {
            recorder.stopAndSave();
        }
    }

    function getInitialView() {
        var view = new RoadQualityView(recorder);
        var delegate = new RoadQualityDelegate(recorder);
        return [ view, delegate ];
    }

}
