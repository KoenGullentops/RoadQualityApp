using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Background as Background;
using Toybox.Time as Time;
using Toybox.Lang as Lang;
using Toybox.System;

// A Data Field cannot read the accelerometer directly (confirmed by an
// on-device crash: "Symbol 'registerSensorDataListener' not available to
// 'Data Field'"), but the Toybox.Sensor module's documented supported
// runtime contexts list "Background" separately from "Data Field" -
// meaning a Data Field app's own background-service context CAN call it.
// This mirrors the well-known "rain radar data field" pattern (fetch
// data periodically in the background, display the last cached value)
// - here the periodic fetch is a brief accelerometer sample instead of a
// web request. Every app referenced from here down to the background
// service must be (:background)-annotated per Connect IQ's background
// code-size rules.
(:background)
class RoadQualityFieldApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new RoadQualityField() ];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [ new RoadQualityServiceDelegate() ];
    }

}
