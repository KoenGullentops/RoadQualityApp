using Toybox.Sensor as Sensor;
using Toybox.Timer as Timer;
using Toybox.Math as Math;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

// Runs the "lift the front wheel ~10cm and drop it" calibration test.
//
// Two things this fixes about the old hardcoded-Z-axis approach: it
// assumed a resting reading of exactly 1.0g on the Z axis, which only
// holds for a perfectly flat mount - any real stem-mount tilt biased
// every roughness reading. And it assumed Z is even the right axis at
// all, which depends on how the device is actually mounted. This
// measures both directly: a short quiet window establishes the real
// per-axis resting reading (the baseline), then the drop's peak
// deviation from that baseline identifies which axis actually responds
// to a vertical bump on this specific mount.
class RoadQualityCalibrator {

    enum {
        AXIS_X,
        AXIS_Y,
        AXIS_Z
    }

    enum {
        STATE_IDLE,
        STATE_BASELINE,
        STATE_CAPTURING,
        STATE_DONE
    }

    // A peak below this suggests the drop wasn't actually done (pure
    // sensor noise while sitting still is typically well under 0.05g).
    const MIN_CONFIDENT_PEAK as Lang.Float = 0.08;

    hidden const BASELINE_SECONDS as Lang.Number = 1;
    hidden const CAPTURE_SECONDS as Lang.Number = 4;

    hidden var state as Lang.Number;
    hidden var timer as Timer.Timer;
    hidden var elapsedSeconds as Lang.Number;

    hidden var baselineSumX as Lang.Float;
    hidden var baselineSumY as Lang.Float;
    hidden var baselineSumZ as Lang.Float;
    hidden var baselineSampleCount as Lang.Number;

    hidden var baseX as Lang.Float;
    hidden var baseY as Lang.Float;
    hidden var baseZ as Lang.Float;

    hidden var peakDeviation as Lang.Float;
    hidden var peakAxis as Lang.Number;

    function initialize() {
        state = STATE_IDLE;
        timer = new Timer.Timer();
        elapsedSeconds = 0;

        baselineSumX = 0.0;
        baselineSumY = 0.0;
        baselineSumZ = 0.0;
        baselineSampleCount = 0;

        // Sane defaults matching the old hardcoded behavior, in case
        // start() is never called (shouldn't happen, but getters should
        // never hand back garbage).
        baseX = 0.0;
        baseY = 0.0;
        baseZ = 1.0;

        peakDeviation = 0.0;
        peakAxis = AXIS_Z;
    }

    function start() as Void {
        state = STATE_BASELINE;
        elapsedSeconds = 0;
        baselineSumX = 0.0;
        baselineSumY = 0.0;
        baselineSumZ = 0.0;
        baselineSampleCount = 0;
        peakDeviation = 0.0;
        peakAxis = AXIS_Z;

        Sensor.registerSensorDataListener(method(:onSensorData), {
            :period => 1,
            :accelerometer => { :enabled => true, :sampleRate => 25 }
        });
        timer.start(method(:onTick), 1000, true);
    }

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        var accel = sensorData.accelerometerData;
        if (accel == null || accel.x == null || accel.y == null || accel.z == null) {
            return;
        }

        var xs = accel.x as Lang.Array<Lang.Number>;
        var ys = accel.y as Lang.Array<Lang.Number>;
        var zs = accel.z as Lang.Array<Lang.Number>;
        var n = xs.size();
        if (ys.size() < n) { n = ys.size(); }
        if (zs.size() < n) { n = zs.size(); }

        for (var i = 0; i < n; i += 1) {
            var xg = xs[i] / 1000.0;
            var yg = ys[i] / 1000.0;
            var zg = zs[i] / 1000.0;

            if (state == STATE_BASELINE) {
                baselineSumX += xg;
                baselineSumY += yg;
                baselineSumZ += zg;
                baselineSampleCount += 1;
            } else if (state == STATE_CAPTURING) {
                trackPeak(xg, yg, zg);
            }
        }
    }

    hidden function trackPeak(xg as Lang.Float, yg as Lang.Float, zg as Lang.Float) as Void {
        var devX = (xg - baseX).abs();
        var devY = (yg - baseY).abs();
        var devZ = (zg - baseZ).abs();

        if (devX > peakDeviation) { peakDeviation = devX; peakAxis = AXIS_X; }
        if (devY > peakDeviation) { peakDeviation = devY; peakAxis = AXIS_Y; }
        if (devZ > peakDeviation) { peakDeviation = devZ; peakAxis = AXIS_Z; }
    }

    function onTick() as Void {
        elapsedSeconds += 1;

        if (state == STATE_BASELINE && elapsedSeconds >= BASELINE_SECONDS) {
            if (baselineSampleCount > 0) {
                baseX = baselineSumX / baselineSampleCount;
                baseY = baselineSumY / baselineSampleCount;
                baseZ = baselineSumZ / baselineSampleCount;
            }
            state = STATE_CAPTURING;
        } else if (state == STATE_CAPTURING && elapsedSeconds >= BASELINE_SECONDS + CAPTURE_SECONDS) {
            finish();
        }

        Ui.requestUpdate();
    }

    hidden function finish() as Void {
        Sensor.unregisterSensorDataListener();
        timer.stop();
        state = STATE_DONE;
    }

    // Best-effort cleanup if the user navigates away mid-capture.
    function cancel() as Void {
        try {
            Sensor.unregisterSensorDataListener();
        } catch (ex instanceof Lang.Exception) {
        }
        timer.stop();
        state = STATE_IDLE;
    }

    function getState() as Lang.Number { return state; }

    // Seconds remaining in the current phase, for an on-screen countdown.
    function getPhaseSecondsRemaining() as Lang.Number {
        if (state == STATE_BASELINE) {
            return BASELINE_SECONDS - elapsedSeconds;
        }
        if (state == STATE_CAPTURING) {
            return BASELINE_SECONDS + CAPTURE_SECONDS - elapsedSeconds;
        }
        return 0;
    }

    function getBaseX() as Lang.Float { return baseX; }
    function getBaseY() as Lang.Float { return baseY; }
    function getBaseZ() as Lang.Float { return baseZ; }
    function getPeakAxis() as Lang.Number { return peakAxis; }
    function getPeakDeviation() as Lang.Float { return peakDeviation; }
    function isConfident() as Lang.Boolean { return peakDeviation >= MIN_CONFIDENT_PEAK; }

    function getAxisName() as Lang.String {
        if (peakAxis == AXIS_X) { return "X"; }
        if (peakAxis == AXIS_Y) { return "Y"; }
        return "Z";
    }

}
