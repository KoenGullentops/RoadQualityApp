using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Sensor as Sensor;
using Toybox.FitContributor as Fit;
using Toybox.Math as Math;

// Rolling average of road roughness over the trailing 60 seconds
// (a sliding window of the last 60 once-per-second compute() samples).
class RoadQualityField extends Ui.DataField {

    hidden var roughnessField;

    // Accumulates live accelerometer samples between compute() calls.
    hidden var sumSquaredDeviation;
    hidden var sampleCount;

    // Ring buffer holding the last windowSize per-second instantaneous
    // values, plus a running sum so the average is O(1) to update.
    hidden var windowSize;
    hidden var buffer;
    hidden var writeIndex;
    hidden var filledCount;
    hidden var ringSum;

    hidden var currentValue;

    function initialize() {
        DataField.initialize();

        sumSquaredDeviation = 0.0;
        sampleCount = 0;
        currentValue = 0.0;

        windowSize = 60;
        buffer = new [windowSize];
        for (var i = 0; i < windowSize; i += 1) {
            buffer[i] = 0.0;
        }
        writeIndex = 0;
        filledCount = 0;
        ringSum = 0.0;

        roughnessField = createField(
            "roughness_1min_g",
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
        var instant = 0.0;
        if (sampleCount > 0) {
            instant = Math.sqrt(sumSquaredDeviation / sampleCount);
        }
        sumSquaredDeviation = 0.0;
        sampleCount = 0;

        if (filledCount < windowSize) {
            ringSum += instant;
            buffer[writeIndex] = instant;
            filledCount += 1;
        } else {
            ringSum += instant - buffer[writeIndex];
            buffer[writeIndex] = instant;
        }
        writeIndex = (writeIndex + 1) % windowSize;

        currentValue = ringSum / filledCount;

        roughnessField.setData(currentValue);
        return currentValue;
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.22, Gfx.FONT_TINY, "Roughness (1 min)", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.55, Gfx.FONT_NUMBER_MEDIUM, currentValue.format("%.2f"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.85, Gfx.FONT_XTINY, "g avg", Gfx.TEXT_JUSTIFY_CENTER);
    }

}
