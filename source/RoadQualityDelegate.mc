using Toybox.WatchUi as Ui;

class RoadQualityDelegate extends Ui.BehaviorDelegate {

    hidden var recorder;

    function initialize(recorder) {
        BehaviorDelegate.initialize();
        self.recorder = recorder;
    }

    function onSelect() {
        if (recorder.isRecording()) {
            recorder.stop();
        } else {
            recorder.start();
        }
        Ui.requestUpdate();
        return true;
    }

    function onBack() {
        if (recorder.isRecording()) {
            // Stop and save instead of letting Back exit over an open
            // recording session.
            recorder.stop();
            Ui.requestUpdate();
            return true;
        }
        return false;
    }

}
