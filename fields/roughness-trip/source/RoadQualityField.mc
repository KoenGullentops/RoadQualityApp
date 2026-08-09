using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Sensor as Sensor;
using Toybox.FitContributor as Fit;
using Toybox.Math as Math;

// Cumulative average of road roughness since the activity started.
class RoadQualityField extends Ui.DataField {

    hidden var roughnessField as Fit.Field;

    // Accumulates live accelerometer samples between compute() calls.
    hidden var sumSquaredDeviation as Float;
    hidden var sampleCount as Number;

    // Running sum/count of every per-second instantaneous value since the
    // field was initialized (i.e. since the activity started).
    hidden var tripSum as Float;
    hidden var tripCount as Number;

    hidden var currentValue as Float;

    function initialize() {
        DataField.initialize();

        sumSquaredDeviation = 0.0;
        sampleCount = 0;
        tripSum = 0.0;
        tripCount = 0;
        currentValue = 0.0;

        roughnessField = createField(
            "roughness_trip_g",
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
    function onSensorData(sensorData as Sensor.SensorData) as Void {
        var accel = sensorData.accelerometerData;
        if (accel == null || accel.x == null) {
            return;
        }

        var xs = accel.x as Array<Number>;
        var ys = accel.y as Array<Number>;
        var zs = accel.z as Array<Number>;
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
        var instant = 0.0;
        if (sampleCount > 0) {
            instant = Math.sqrt(sumSquaredDeviation / sampleCount);
        }
        sumSquaredDeviation = 0.0;
        sampleCount = 0;

        tripSum += instant;
        tripCount += 1;
        currentValue = tripSum / tripCount;

        roughnessField.setData(currentValue);
        return currentValue;
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.22, Gfx.FONT_TINY, "Roughness (Trip)", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.55, Gfx.FONT_NUMBER_MEDIUM, currentValue.format("%.2f"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.85, Gfx.FONT_XTINY, "g avg", Gfx.TEXT_JUSTIFY_CENTER);
    }

}
