using Toybox.System;
using Toybox.Background as Background;
using Toybox.Sensor as Sensor;
using Toybox.Math as Math;
using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.Time as Time;

// Runs in the background every 5 minutes (the minimum interval Connect IQ
// allows for a temporal event). Samples the accelerometer for one short
// burst, computes an instantaneous roughness reading the same way the
// standalone app does, stores it as the latest snapshot, folds it into a
// running trip sum/count for a trip-wide average, and exits - well within
// the 30-second background execution budget. RoadQualityField.onTimerReset()
// clears tripSum/tripCount when a ride ends, so the average is scoped to
// one trip rather than accumulating forever across rides.
(:background)
class RoadQualityServiceDelegate extends System.ServiceDelegate {

    // At one point every 5 minutes, 100 points covers over 8 hours of
    // riding before the oldest snapshot gets dropped.
    hidden const HISTORY_MAX as Lang.Number = 100;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        Sensor.registerSensorDataListener(method(:onSensorData), {
            :period => 4,
            :accelerometer => { :enabled => true, :sampleRate => 25 }
        });
    }

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        Sensor.unregisterSensorDataListener();

        var roughness = 0.0;
        var accel = sensorData.accelerometerData;

        if (accel != null && accel.x != null && accel.y != null && accel.z != null) {
            var xs = accel.x as Lang.Array<Lang.Number>;
            var ys = accel.y as Lang.Array<Lang.Number>;
            var zs = accel.z as Lang.Array<Lang.Number>;
            var n = xs.size();
            if (ys.size() < n) { n = ys.size(); }
            if (zs.size() < n) { n = zs.size(); }

            if (n > 0) {
                var sumSquaredDeviation = 0.0;
                for (var i = 0; i < n; i += 1) {
                    var xg = xs[i] / 1000.0;
                    var yg = ys[i] / 1000.0;
                    var zg = zs[i] / 1000.0;
                    var magnitude = Math.sqrt(xg * xg + yg * yg + zg * zg);
                    var deviation = magnitude - 1.0;
                    sumSquaredDeviation += deviation * deviation;
                }
                roughness = Math.sqrt(sumSquaredDeviation / n);
            }
        }

        Storage.setValue("lastRoughness", roughness);
        Storage.setValue("lastUpdatedAt", Time.now().value());

        var tripSum = Storage.getValue("tripSum");
        var tripCount = Storage.getValue("tripCount");
        var newSum = (tripSum == null ? 0.0 : tripSum as Lang.Float) + roughness;
        var newCount = (tripCount == null ? 0 : tripCount as Lang.Number) + 1;
        Storage.setValue("tripSum", newSum);
        Storage.setValue("tripCount", newCount);

        var stored = Storage.getValue("history");
        var history = stored == null ? ([] as Lang.Array<Lang.Float>) : (stored as Lang.Array<Lang.Float>);
        history.add(roughness);
        if (history.size() > HISTORY_MAX) {
            history = history.slice(1, null) as Lang.Array<Lang.Float>;
        }
        Storage.setValue("history", history);

        Background.exit(null);
    }

}
