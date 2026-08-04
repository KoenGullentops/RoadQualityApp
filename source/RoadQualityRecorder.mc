using Toybox.ActivityRecording as Record;
using Toybox.SensorLogging as SensorLogging;
using Toybox.Position as Position;
using Toybox.System as Sys;

// Owns the FIT activity-recording session and the raw-accelerometer
// SensorLogger attached to it. A Connect IQ Data Field cannot attach a
// SensorLogger (it only ever gets a session someone else already created),
// so this app creates its own session instead of running as a data field
// inside the stock Ride profile.
class RoadQualityRecorder {

    hidden var session;
    hidden var sensorLogger;
    hidden var recording;
    hidden var startMoment;
    hidden var positionEnabled;

    function initialize() {
        recording = false;
        session = null;
        sensorLogger = null;
        positionEnabled = false;
        startMoment = 0;
    }

    function isRecording() {
        return recording;
    }

    function start() {
        if (recording) {
            return;
        }

        // 25 Hz raw accelerometer, written straight into the FIT
        // activity file's Accelerometer Data messages.
        sensorLogger = new SensorLogging.SensorLogger({
            :accelerometer => { :enabled => true }
        });

        session = Record.createSession({
            :name => "Road Quality",
            :sport => Record.SPORT_CYCLING,
            :sensorLogger => sensorLogger
        });

        // Powers up GPS so position_lat/position_long land in each FIT
        // record alongside the accelerometer data; we don't need the
        // callback payload itself.
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        positionEnabled = true;

        session.start();
        recording = true;
        startMoment = Sys.getTimer();
    }

    function stop() {
        if (!recording) {
            return;
        }

        session.stop();
        session.save();
        session = null;
        sensorLogger = null;

        if (positionEnabled) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
            positionEnabled = false;
        }

        recording = false;
    }

    function onPosition(info) {
    }

    function getElapsedString() {
        if (!recording) {
            return "00:00";
        }
        var elapsedSec = (Sys.getTimer() - startMoment) / 1000;
        var mins = elapsedSec / 60;
        var secs = elapsedSec % 60;
        return mins.format("%02d") + ":" + secs.format("%02d");
    }

    // Best-effort: the exact SensorLoggingStats field names vary by SDK
    // version, so this never throws past this method if the API differs.
    function getSampleCountString() {
        if (sensorLogger == null) {
            return "";
        }
        try {
            var stats = sensorLogger.getStats2(:accelerometer);
            if (stats != null && stats has :sampleCount) {
                return stats.sampleCount.toString() + " samples";
            }
        } catch (ex) {
        }
        return "";
    }

    function getStatusLine() {
        return recording ? "Keep device mounted - select to stop" : "Select to start ride logging";
    }

}
