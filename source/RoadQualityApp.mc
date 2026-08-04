using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class RoadQualityApp extends App.AppBase {

    hidden var recorder;

    function initialize() {
        AppBase.initialize();
        recorder = new RoadQualityRecorder();
    }

    function onStart(state) {
    }

    function onStop(state) {
        // Safety net: make sure a FIT session that's still open gets
        // stopped and saved if the app is killed mid-ride.
        if (recorder.isRecording()) {
            recorder.stop();
        }
    }

    function getInitialView() {
        var view = new RoadQualityView(recorder);
        var delegate = new RoadQualityDelegate(recorder);
        return [view, delegate];
    }

}
