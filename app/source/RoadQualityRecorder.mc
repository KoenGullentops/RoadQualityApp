using Toybox.ActivityRecording as Recording;
using Toybox.Activity as Activity;
using Toybox.Sensor as Sensor;
using Toybox.FitContributor as Fit;
using Toybox.Timer as Timer;
using Toybox.Math as Math;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;
using Toybox.Position as Position;

// Owns the FIT recording session, live accelerometer sampling, and the
// three rolling road-roughness averages (1 min / 5 min / trip). A
// standalone app - not a Data Field - because Data Fields cannot read
// live accelerometer data at all on this device (confirmed by an actual
// device crash log: "Symbol 'registerSensorDataListener' not available to
// 'Data Field'", and independently corroborated for Sensor.getInfo() too).
// Owning our own ActivityRecording session is the only way to get both.
class RoadQualityRecorder {

    enum {
        STATE_STOPPED,
        STATE_RECORDING
    }

    hidden var state as Lang.Number;
    hidden var session as Recording.Session?;
    hidden var timer as Timer.Timer;

    hidden var fieldRaw as Fit.Field?;
    hidden var field1min as Fit.Field?;
    hidden var field5min as Fit.Field?;
    hidden var fieldTrip as Fit.Field?;
    hidden var fieldAccelX as Fit.Field?;
    hidden var fieldAccelY as Fit.Field?;
    hidden var fieldAccelZ as Fit.Field?;

    // Accumulates live accelerometer samples between once-per-second ticks.
    hidden var sumSquaredDeviation as Lang.Float;
    hidden var sumX as Lang.Float;
    hidden var sumY as Lang.Float;
    hidden var sumZ as Lang.Float;
    hidden var sampleCount as Lang.Number;

    // Set by the calibration screen (RoadQualityCalibrator) before this
    // recorder ever starts - which axis actually responds to a bump on
    // this specific mount, and what each axis reads at rest (its own
    // resting tilt, not an assumed 1.0g). Defaults here match the old
    // hardcoded-Z-at-1g behavior, purely so getters never hand back
    // garbage if start() were somehow called before calibration.
    hidden var calibratedAxis as Lang.Number;
    hidden var calibratedBaseX as Lang.Float;
    hidden var calibratedBaseY as Lang.Float;
    hidden var calibratedBaseZ as Lang.Float;

    // 1-minute sliding window (ring buffer + running sum, O(1) to update).
    hidden var buffer1 as Lang.Array<Lang.Float>;
    hidden var writeIndex1 as Lang.Number;
    hidden var filledCount1 as Lang.Number;
    hidden var ringSum1 as Lang.Float;

    // 5-minute sliding window.
    hidden var buffer5 as Lang.Array<Lang.Float>;
    hidden var writeIndex5 as Lang.Number;
    hidden var filledCount5 as Lang.Number;
    hidden var ringSum5 as Lang.Float;

    // Cumulative average since recording started.
    hidden var tripSum as Lang.Float;
    hidden var tripCount as Lang.Number;

    hidden var value1min as Lang.Float;
    hidden var value5min as Lang.Float;
    hidden var valueTrip as Lang.Float;

    // Whole-trip history graph: a fixed-size buffer that automatically
    // halves its resolution (doubling the seconds-per-point) whenever it
    // fills up, so it can represent a ride of any length in bounded
    // memory - recent history at higher resolution, older history coarser.
    hidden const HISTORY_MAX as Lang.Number = 120;
    hidden var history as Lang.Array<Lang.Float>;
    hidden var historyCount as Lang.Number;
    hidden var historyMaxValue as Lang.Float;
    hidden var historyBucketTarget as Lang.Number;
    hidden var historyBucketSum as Lang.Float;
    hidden var historyBucketCount as Lang.Number;

    // GPS breadcrumb trail for the map screen: same bounded/downsampling
    // technique as the roughness history, applied to lat/lon instead of a
    // single scalar - so a ride of any length still fits in a fixed
    // number of points. gpsRoughness carries the same bucket's average
    // instantaneous roughness alongside each point, so the map screen can
    // color each breadcrumb segment by how rough that stretch actually was.
    hidden const GPS_HISTORY_MAX as Lang.Number = 120;
    hidden var gpsLat as Lang.Array<Lang.Double>;
    hidden var gpsLon as Lang.Array<Lang.Double>;
    hidden var gpsRoughness as Lang.Array<Lang.Float>;
    hidden var gpsCount as Lang.Number;
    hidden var gpsBucketTarget as Lang.Number;
    hidden var gpsBucketLatSum as Lang.Double;
    hidden var gpsBucketLonSum as Lang.Double;
    hidden var gpsBucketRoughnessSum as Lang.Float;
    hidden var gpsBucketCount as Lang.Number;

    // Set when start() fails, so the view can show what went wrong
    // instead of the app just crashing to the system error screen.
    hidden var lastError as Lang.String?;

    // Set when opening the map screen fails; shown on the main screen's
    // status line without hiding the rest of the dashboard.
    hidden var mapError as Lang.String?;

    function initialize() {
        state = STATE_STOPPED;
        session = null;
        timer = new Timer.Timer();
        lastError = null;
        mapError = null;

        buffer1 = new [60] as Lang.Array<Lang.Float>;
        buffer5 = new [300] as Lang.Array<Lang.Float>;
        history = new [HISTORY_MAX] as Lang.Array<Lang.Float>;
        gpsLat = new [GPS_HISTORY_MAX] as Lang.Array<Lang.Double>;
        gpsLon = new [GPS_HISTORY_MAX] as Lang.Array<Lang.Double>;
        gpsRoughness = new [GPS_HISTORY_MAX] as Lang.Array<Lang.Float>;

        sumSquaredDeviation = 0.0;
        sumX = 0.0;
        sumY = 0.0;
        sumZ = 0.0;
        sampleCount = 0;

        calibratedAxis = RoadQualityCalibrator.AXIS_Z;
        calibratedBaseX = 0.0;
        calibratedBaseY = 0.0;
        calibratedBaseZ = 1.0;

        writeIndex1 = 0;
        filledCount1 = 0;
        ringSum1 = 0.0;

        writeIndex5 = 0;
        filledCount5 = 0;
        ringSum5 = 0.0;

        tripSum = 0.0;
        tripCount = 0;

        historyCount = 0;
        historyMaxValue = 0.05;
        historyBucketTarget = 1;
        historyBucketSum = 0.0;
        historyBucketCount = 0;

        gpsCount = 0;
        gpsBucketTarget = 1;
        gpsBucketLatSum = 0.0d;
        gpsBucketLonSum = 0.0d;
        gpsBucketRoughnessSum = 0.0;
        gpsBucketCount = 0;

        value1min = 0.0;
        value5min = 0.0;
        valueTrip = 0.0;

        resetAccumulators();
    }

    // Re-zeroes everything for a fresh recording. Safe to call again from
    // initialize() (the ring buffers are already allocated by then, this
    // just zeroes their contents) as well as from start().
    hidden function resetAccumulators() as Void {
        sumSquaredDeviation = 0.0;
        sumX = 0.0;
        sumY = 0.0;
        sumZ = 0.0;
        sampleCount = 0;

        for (var i = 0; i < 60; i += 1) {
            buffer1[i] = 0.0;
        }
        writeIndex1 = 0;
        filledCount1 = 0;
        ringSum1 = 0.0;

        for (var i = 0; i < 300; i += 1) {
            buffer5[i] = 0.0;
        }
        writeIndex5 = 0;
        filledCount5 = 0;
        ringSum5 = 0.0;

        tripSum = 0.0;
        tripCount = 0;

        historyCount = 0;
        historyMaxValue = 0.05;
        historyBucketTarget = 1;
        historyBucketSum = 0.0;
        historyBucketCount = 0;

        gpsCount = 0;
        gpsBucketTarget = 1;
        gpsBucketLatSum = 0.0d;
        gpsBucketLonSum = 0.0d;
        gpsBucketRoughnessSum = 0.0;
        gpsBucketCount = 0;
    }

    function isRecording() as Lang.Boolean {
        return state == STATE_RECORDING;
    }

    function toggle() as Void {
        if (state == STATE_STOPPED) {
            start();
        } else {
            stopAndSave();
        }
    }

    // Called once by RoadQualityCalibrationDelegate after the user
    // accepts a lift-and-drop calibration result, before this recorder
    // ever starts. axis is one of RoadQualityCalibrator.AXIS_X/Y/Z; the
    // base* values are each axis's own resting reading in g.
    function setCalibration(axis as Lang.Number, baseX as Lang.Float, baseY as Lang.Float, baseZ as Lang.Float) as Void {
        calibratedAxis = axis;
        calibratedBaseX = baseX;
        calibratedBaseY = baseY;
        calibratedBaseZ = baseZ;
    }

    function start() as Void {
        resetAccumulators();
        value1min = 0.0;
        value5min = 0.0;
        valueTrip = 0.0;
        lastError = null;

        try {
            session = Recording.createSession({
                :name => "Road Quality",
                :sport => Activity.SPORT_CYCLING,
                :subSport => Activity.SUB_SPORT_GENERIC
            });

            fieldRaw = session.createField(
                "roughness_raw_g", 0, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );
            field1min = session.createField(
                "roughness_1min_g", 1, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );
            field5min = session.createField(
                "roughness_5min_g", 2, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );
            fieldTrip = session.createField(
                "roughness_trip_g", 3, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );
            fieldAccelX = session.createField(
                "accel_x_g", 4, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );
            fieldAccelY = session.createField(
                "accel_y_g", 5, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );
            fieldAccelZ = session.createField(
                "accel_z_g", 6, Fit.DATA_TYPE_FLOAT,
                { :mesgType => Fit.MESG_TYPE_RECORD, :units => "g" }
            );

            session.start();

            // Creating/starting a session does NOT turn the GPS receiver
            // on by itself - confirmed against the local SDK docs
            // ("To enable the GPS call the Position.enableLocationEvents()
            // method"), and this was the actual reason recorded FIT files
            // had no position/speed/distance despite genuine outdoor
            // testing with a real GPS fix available.
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPositionEvent));

            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => 25 }
            });

            timer.start(method(:onTimerTick), 1000, true);

            state = STATE_RECORDING;
        } catch (ex instanceof Lang.Exception) {
            lastError = ex.getErrorMessage();
            abandonSession();
            state = STATE_STOPPED;
        }
    }

    // Required listener for Position.enableLocationEvents() - we don't
    // need to do anything with the update ourselves, since
    // Activity.getActivityInfo() already reflects the live fix once GPS
    // is actually turned on, which is what this call is for.
    function onPositionEvent(posInfo as Position.Info) as Void {
    }

    // Best-effort cleanup of a partially-started session after start()
    // fails partway through. Each call is independently guarded since we
    // don't know how far start() got before it threw.
    hidden function abandonSession() as Void {
        timer.stop();

        try {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        } catch (ex instanceof Lang.Exception) {
        }

        try {
            Sensor.unregisterSensorDataListener();
        } catch (ex instanceof Lang.Exception) {
        }

        if (session != null) {
            try {
                session.stop();
            } catch (ex instanceof Lang.Exception) {
            }
            try {
                session.discard();
            } catch (ex instanceof Lang.Exception) {
            }
            session = null;
        }
    }

    function getLastError() as Lang.String? {
        return lastError;
    }

    function getMapError() as Lang.String? {
        return mapError;
    }

    // Lets the map screen surface its own failures on the main screen's
    // status line (a separate field from lastError, which takes over the
    // whole screen for a failed recording start - a failed map open
    // shouldn't hide the roughness values that are still working fine).
    function setMapError(message as Lang.String) as Void {
        mapError = message;
    }

    function clearMapError() as Void {
        mapError = null;
    }

    function stopAndSave() as Void {
        timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        Sensor.unregisterSensorDataListener();

        if (session != null) {
            session.stop();
            session.save();
            session = null;
        }

        state = STATE_STOPPED;
    }

    // Weighted toward whichever axis the lift-and-drop calibration
    // (RoadQualityCalibrator) identified as the one that actually
    // responds to a vertical bump on this specific mount, deviation
    // measured from that axis's own calibrated resting reading rather
    // than an assumed 1.0g - a tilted stem mount otherwise biases every
    // reading, since gravity doesn't land exactly on one axis. The other
    // two axes mostly reflect braking, cornering, and pedaling forces
    // rather than road surface, so they're weighted down rather than
    // dropped entirely - a rough patch still jostles the mount sideways
    // somewhat. This replaced an earlier hardcoded-Z-at-1g version.
    hidden const PRIMARY_WEIGHT as Lang.Float = 1.0;
    hidden const SECONDARY_WEIGHT as Lang.Float = 0.25;

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

            sumX += xg;
            sumY += yg;
            sumZ += zg;

            var devX = xg - calibratedBaseX;
            var devY = yg - calibratedBaseY;
            var devZ = zg - calibratedBaseZ;

            var weighted = 0.0;
            if (calibratedAxis == RoadQualityCalibrator.AXIS_X) {
                weighted = (PRIMARY_WEIGHT * devX * devX) + (SECONDARY_WEIGHT * ((devY * devY) + (devZ * devZ)));
            } else if (calibratedAxis == RoadQualityCalibrator.AXIS_Y) {
                weighted = (PRIMARY_WEIGHT * devY * devY) + (SECONDARY_WEIGHT * ((devX * devX) + (devZ * devZ)));
            } else {
                weighted = (PRIMARY_WEIGHT * devZ * devZ) + (SECONDARY_WEIGHT * ((devX * devX) + (devY * devY)));
            }

            sumSquaredDeviation += weighted;
            sampleCount += 1;
        }
    }

    function onTimerTick() as Void {
        var instant = 0.0;
        var avgX = 0.0;
        var avgY = 0.0;
        var avgZ = 0.0;
        if (sampleCount > 0) {
            instant = Math.sqrt(sumSquaredDeviation / sampleCount);
            avgX = sumX / sampleCount;
            avgY = sumY / sampleCount;
            avgZ = sumZ / sampleCount;
        }
        sumSquaredDeviation = 0.0;
        sumX = 0.0;
        sumY = 0.0;
        sumZ = 0.0;
        sampleCount = 0;

        if (filledCount1 < 60) {
            ringSum1 += instant;
            buffer1[writeIndex1] = instant;
            filledCount1 += 1;
        } else {
            ringSum1 += instant - buffer1[writeIndex1];
            buffer1[writeIndex1] = instant;
        }
        writeIndex1 = (writeIndex1 + 1) % 60;
        value1min = ringSum1 / filledCount1;

        if (filledCount5 < 300) {
            ringSum5 += instant;
            buffer5[writeIndex5] = instant;
            filledCount5 += 1;
        } else {
            ringSum5 += instant - buffer5[writeIndex5];
            buffer5[writeIndex5] = instant;
        }
        writeIndex5 = (writeIndex5 + 1) % 300;
        value5min = ringSum5 / filledCount5;

        tripSum += instant;
        tripCount += 1;
        valueTrip = tripSum / tripCount;

        if (fieldRaw != null) { fieldRaw.setData(instant); }
        if (field1min != null) { field1min.setData(value1min); }
        if (field5min != null) { field5min.setData(value5min); }
        if (fieldTrip != null) { fieldTrip.setData(valueTrip); }
        if (fieldAccelX != null) { fieldAccelX.setData(avgX); }
        if (fieldAccelY != null) { fieldAccelY.setData(avgY); }
        if (fieldAccelZ != null) { fieldAccelZ.setData(avgZ); }

        recordHistory(instant);
        recordGpsBreadcrumb(instant);

        Ui.requestUpdate();
    }

    // Folds the current GPS fix (if any) into the breadcrumb trail used
    // by the map screen, once per second alongside everything else. Also
    // carries this second's instantaneous roughness reading along with
    // the point, so the map can color each segment by how rough that
    // stretch was.
    hidden function recordGpsBreadcrumb(instant as Lang.Float) as Void {
        var info = Activity.getActivityInfo();

        var loc = info.currentLocation;
        var quality = info.currentLocationAccuracy;
        if (loc == null || quality == null || quality == Position.QUALITY_NOT_AVAILABLE) {
            return;
        }

        var degrees = loc.toDegrees();
        recordGpsPoint(degrees[0], degrees[1], instant);
    }

    hidden function recordGpsPoint(lat as Lang.Double, lon as Lang.Double, instant as Lang.Float) as Void {
        gpsBucketLatSum += lat;
        gpsBucketLonSum += lon;
        gpsBucketRoughnessSum += instant;
        gpsBucketCount += 1;

        if (gpsBucketCount < gpsBucketTarget) {
            return;
        }

        var avgLat = gpsBucketLatSum / gpsBucketCount;
        var avgLon = gpsBucketLonSum / gpsBucketCount;
        var avgRoughness = gpsBucketRoughnessSum / gpsBucketCount;
        gpsBucketLatSum = 0.0d;
        gpsBucketLonSum = 0.0d;
        gpsBucketRoughnessSum = 0.0;
        gpsBucketCount = 0;

        if (gpsCount >= GPS_HISTORY_MAX) {
            var newCount = GPS_HISTORY_MAX / 2;
            for (var i = 0; i < newCount; i += 1) {
                gpsLat[i] = (gpsLat[2 * i] + gpsLat[2 * i + 1]) / 2.0d;
                gpsLon[i] = (gpsLon[2 * i] + gpsLon[2 * i + 1]) / 2.0d;
                gpsRoughness[i] = (gpsRoughness[2 * i] + gpsRoughness[2 * i + 1]) / 2.0;
            }
            gpsCount = newCount;
            gpsBucketTarget *= 2;
        }

        gpsLat[gpsCount] = avgLat;
        gpsLon[gpsCount] = avgLon;
        gpsRoughness[gpsCount] = avgRoughness;
        gpsCount += 1;
    }

    // Folds one more once-per-second instantaneous reading into the
    // whole-trip history graph, halving the buffer's resolution whenever
    // it fills so a ride of any length fits in HISTORY_MAX points.
    hidden function recordHistory(instant as Lang.Float) as Void {
        historyBucketSum += instant;
        historyBucketCount += 1;

        if (historyBucketCount < historyBucketTarget) {
            return;
        }

        var bucketAvg = historyBucketSum / historyBucketCount;
        historyBucketSum = 0.0;
        historyBucketCount = 0;

        if (historyCount >= HISTORY_MAX) {
            var newCount = HISTORY_MAX / 2;
            for (var i = 0; i < newCount; i += 1) {
                history[i] = (history[2 * i] + history[2 * i + 1]) / 2.0;
            }
            historyCount = newCount;
            historyBucketTarget *= 2;
        }

        history[historyCount] = bucketAvg;
        historyCount += 1;

        if (bucketAvg > historyMaxValue) {
            historyMaxValue = bucketAvg;
        }
    }

    function getValue1Min() as Lang.Float { return value1min; }
    function getValue5Min() as Lang.Float { return value5min; }
    function getValueTrip() as Lang.Float { return valueTrip; }

    function getHistory() as Lang.Array<Lang.Float> { return history; }
    function getHistoryCount() as Lang.Number { return historyCount; }
    function getHistoryMaxValue() as Lang.Float { return historyMaxValue; }

    function getGpsLat() as Lang.Array<Lang.Double> { return gpsLat; }
    function getGpsLon() as Lang.Array<Lang.Double> { return gpsLon; }
    function getGpsRoughness() as Lang.Array<Lang.Float> { return gpsRoughness; }
    function getGpsCount() as Lang.Number { return gpsCount; }

}
