using Toybox.System;
using Toybox.Background as Background;
using Toybox.Sensor as Sensor;
using Toybox.Math as Math;
using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;

// Runs in the background every 5 minutes (the minimum interval Connect IQ
// allows for a temporal event). Samples the accelerometer for one short
// burst, computes an instantaneous roughness reading the same way the
// standalone app does, stores it, and exits - well within the 30-second
// background execution budget.
(:background)
class RoadQualityServiceDelegate extends System.ServiceDelegate {

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

        Background.exit(null);
    }

}
