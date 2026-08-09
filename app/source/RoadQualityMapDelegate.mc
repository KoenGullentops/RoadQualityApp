using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;

// Any tap, select, or back on the map screen returns to the main screen.
class RoadQualityMapDelegate extends Ui.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        Ui.popView(Ui.SLIDE_RIGHT);
        return true;
    }

    function onSelect() as Lang.Boolean {
        Ui.popView(Ui.SLIDE_RIGHT);
        return true;
    }

    function onTap(clickEvent) as Lang.Boolean {
        Ui.popView(Ui.SLIDE_RIGHT);
        return true;
    }

}
