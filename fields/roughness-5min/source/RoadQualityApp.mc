using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class RoadQualityApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    // Data Field apps have no interactive delegate; the field itself is
    // the whole app.
    function getInitialView() {
        return [ new RoadQualityField() ];
    }

}
