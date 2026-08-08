using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Sensor as Sensor;
using Toybox.FitContributor as Fit;
using Toybox.Lang as Lang;
using Toybox.Math as Math;

// A cycling data field (tile) that reads the live accelerometer and shows
// a rolling road-roughness score. Unlike a raw SensorLogger (which can only
// be attached by the app that creates the FIT recording session), a plain
// Sensor.registerSensorDataListener works fine inside a Data Field, since
// it just reads live sensor events rather than owning the recording.
class RoadQualityField extends Ui.DataField {

    hidden var roughnessField;
    hidden var sumSquaredDeviation;
    hidden var sampleCount;
    hidden var currentValue;

    function initialize() {
        DataField.initialize();

        sumSquaredDeviation = 0.0;
        sampleCount = 0;
        currentValue = 0.0;

        // Persists a computed roughness value into the FIT activity file
        // once per compute() cycle (~1 Hz), so it's still exportable
        // afterwards even though we're not logging raw samples.
        roughnessField = createField(
            "road_roughness",
            0,
            Fit.DATA_TYPE_FLOAT,
            { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
        );

        Sensor.registerSensorDataListener(method(:onSensorData), {
            :accelerometer => { :enabled => true }
        });
    }

    // sensorData.accelerometerData.x/y/z are each Arrays of Numbers, in
    // milli-g, possibly containing several samples gathered since the last
    // callback. We fold them into a running sum-of-squared-deviation so
    // compute() can produce an RMS without holding onto every raw sample.
    function onSensorData(sensorData) {
        var accel = sensorData.accelerometerData;
        if (accel == null || accel.x == null) {
            return;
        }

        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        var n = xs.size();

        for (var i = 0; i < n; i += 1) {
            var xg = xs[i] / 1000.0;
            var yg = ys[i] / 1000.0;
            var zg = zs[i] / 1000.0;
            var magnitude = Math.sqrt(xg * xg + yg * yg + zg * zg);
            var deviation = magnitude - 1.0;
            sumSquaredDeviation += deviation * deviation;
            sampleCount += 1;
        }
    }

    function compute(info) {
        if (sampleCount > 0) {
            currentValue = Math.sqrt(sumSquaredDeviation / sampleCount);
        }
        sumSquaredDeviation = 0.0;
        sampleCount = 0;

        roughnessField.setData(currentValue);
        return currentValue;
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.22, Gfx.FONT_TINY, "Road Roughness", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.55, Gfx.FONT_NUMBER_MEDIUM, currentValue.format("%.2f"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.85, Gfx.FONT_XTINY, "g RMS", Gfx.TEXT_JUSTIFY_CENTER);
    }

}
