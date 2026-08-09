using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;

// BehaviorDelegate normalizes both physical-button and touchscreen input,
// which matters here since the Edge 1030 Plus supports both.
class RoadQualityDelegate extends Ui.BehaviorDelegate {

    hidden var recorder as RoadQualityRecorder;

    function initialize(recorder as RoadQualityRecorder) {
        BehaviorDelegate.initialize();
        self.recorder = recorder;
    }

    function onSelect() as Lang.Boolean {
        recorder.toggle();
        Ui.requestUpdate();
        return true;
    }

    function onTap(clickEvent) as Lang.Boolean {
        recorder.toggle();
        Ui.requestUpdate();
        return true;
    }

    // Swipe or the physical page button opens the map screen. Wrapped in
    // try/catch since MapView is known to be less reliable than the rest
    // of this app's APIs - better to show the actual error on screen than
    // crash and need another log pull to find out what happened.
    function onNextPage() as Lang.Boolean {
        recorder.clearMapError();
        try {
            Ui.pushView(
                new RoadQualityMapView(recorder),
                new RoadQualityMapDelegate(),
                Ui.SLIDE_LEFT
            );
        } catch (ex instanceof Lang.Exception) {
            recorder.setMapError(ex.getErrorMessage());
            Ui.requestUpdate();
        }
        return true;
    }

}
