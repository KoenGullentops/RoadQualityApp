using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.Activity as Activity;
using Toybox.Position as Position;

class RoadQualityView extends Ui.View {

    hidden var recorder as RoadQualityRecorder;

    function initialize(recorder as RoadQualityRecorder) {
        View.initialize();
        self.recorder = recorder;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.04, Gfx.FONT_XTINY, "DS2.0 Road Quality Index", Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine((w * 0.15).toNumber(), (h * 0.075).toNumber(), (w * 0.85).toNumber(), (h * 0.075).toNumber());
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);

        drawGpsIndicator(dc, w, h);

        var error = recorder.getLastError();
        if (error != null) {
            dc.drawText(w / 2, h * 0.18, Gfx.FONT_XTINY, "Error - tap to retry", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.30, Gfx.FONT_XTINY, error, Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var status = recorder.isRecording()
            ? "RECORDING - tap to stop & save"
            : "Tap to start recording";
        var mapError = recorder.getMapError();
        if (mapError != null) {
            status = "Map error: " + mapError;
        }
        dc.drawText(w / 2, h * 0.14, Gfx.FONT_XTINY, status, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.24, Gfx.FONT_TINY,
            "1m " + recorder.getValue1Min().format("%.2f")
            + "  5m " + recorder.getValue5Min().format("%.2f")
            + "  Trip " + recorder.getValueTrip().format("%.2f") + " g",
            Gfx.TEXT_JUSTIFY_CENTER);

        var graphX = (w * 0.06).toNumber();
        var graphY = (h * 0.27).toNumber();
        var graphW = (w * 0.88).toNumber();
        var graphH = (h * 0.31).toNumber();
        drawGraph(dc, graphX, graphY, graphW, graphH);

        drawStats(dc, w, h);
    }

    // Small top-right glanceable GPS fix indicator, since a bad or absent
    // fix silently means no position/speed/distance/map breadcrumb - this
    // used to fail completely invisibly (see the GPS-enable bug in
    // README's Known caveats). Colored so a problem is visible without
    // reading the text: green/yellow good-to-marginal fix, orange poor,
    // gray a stale last-known fix, red no fix at all.
    hidden function drawGpsIndicator(dc as Gfx.Dc, w as Lang.Number, h as Lang.Number) as Void {
        var info = Activity.getActivityInfo();
        var quality = info != null ? info.currentLocationAccuracy : null;

        var color = Gfx.COLOR_RED;
        var text = "GPS --";
        if (quality == Position.QUALITY_GOOD) {
            color = Gfx.COLOR_GREEN;
            text = "GPS";
        } else if (quality == Position.QUALITY_USABLE) {
            color = Gfx.COLOR_YELLOW;
            text = "GPS";
        } else if (quality == Position.QUALITY_POOR) {
            color = Gfx.COLOR_ORANGE;
            text = "GPS";
        } else if (quality == Position.QUALITY_LAST_KNOWN) {
            color = Gfx.COLOR_DK_GRAY;
            text = "GPS?";
        }

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w * 0.94, h * 0.04, Gfx.FONT_XTINY, text, Gfx.TEXT_JUSTIFY_RIGHT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
    }

    // Ride basics as a 2x2 grid filling the remaining space below the
    // graph, values as large as that space allows. Pulled from the
    // activity info the recording session already exposes - no separate
    // GPS/HR reading needed on our part.
    hidden function drawStats(dc as Gfx.Dc, w as Lang.Number, h as Lang.Number) as Void {
        var info = Activity.getActivityInfo();

        var speedText = "--";
        var distanceText = "--";
        var timeText = "--:--";
        var hrText = "--";

        if (info != null) {
            if (info.currentSpeed != null) {
                speedText = (info.currentSpeed * 3.6).format("%.1f");
            }
            if (info.elapsedDistance != null) {
                distanceText = (info.elapsedDistance / 1000.0).format("%.2f");
            }
            if (info.elapsedTime != null) {
                timeText = formatElapsedTime(info.elapsedTime);
            }
            if (info.currentHeartRate != null) {
                hrText = info.currentHeartRate.format("%d");
            }
        }

        var statsTop = h * 0.60;
        var statsBottom = h * 0.98;
        var rowH = (statsBottom - statsTop) / 2;

        var col1X = (w * 0.27).toNumber();
        var col2X = (w * 0.73).toNumber();

        var row1LabelY = (statsTop + rowH * 0.05).toNumber();
        var row1ValueY = (statsTop + rowH * 0.32).toNumber();
        var row2LabelY = (statsTop + rowH * 1.05).toNumber();
        var row2ValueY = (statsTop + rowH * 1.32).toNumber();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);

        dc.drawText(col1X, row1LabelY, Gfx.FONT_XTINY, "SPEED km/h", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(col1X, row1ValueY, Gfx.FONT_NUMBER_MEDIUM, speedText, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(col2X, row1LabelY, Gfx.FONT_XTINY, "DISTANCE km", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(col2X, row1ValueY, Gfx.FONT_NUMBER_MEDIUM, distanceText, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(col1X, row2LabelY, Gfx.FONT_XTINY, "TIME", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(col1X, row2ValueY, Gfx.FONT_NUMBER_MEDIUM, timeText, Gfx.TEXT_JUSTIFY_CENTER);

        dc.drawText(col2X, row2LabelY, Gfx.FONT_XTINY, "HR bpm", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(col2X, row2ValueY, Gfx.FONT_NUMBER_MEDIUM, hrText, Gfx.TEXT_JUSTIFY_CENTER);
    }

    hidden function formatElapsedTime(elapsedMs as Lang.Number) as Lang.String {
        var totalSeconds = elapsedMs / 1000;
        var hours = totalSeconds / 3600;
        var minutes = (totalSeconds % 3600) / 60;
        var seconds = totalSeconds % 60;

        if (hours > 0) {
            return hours.format("%d") + ":" + minutes.format("%02d") + ":" + seconds.format("%02d");
        }
        return minutes.format("%02d") + ":" + seconds.format("%02d");
    }

    // Draws the whole-trip roughness trace as a rounded card: filled
    // area under the curve, the line itself color-coded green/yellow/red
    // by roughness (same gradient as the map screen and docs/ web
    // viewer), oldest reading at the left edge and most recent at the
    // right, with the latest point highlighted. Y-axis is scaled to the
    // 95th percentile of the visible history rather than the running
    // max, so a single outlier spike can't squash the rest of the
    // ride's real variation down near the bottom of the graph - same
    // fix already applied to the map/web viewer's color scale, applied
    // here to this graph's vertical scale too.
    hidden const GRAPH_CARD_COLOR as Gfx.ColorType = 0x202020;
    hidden const GRAPH_GRID_COLOR as Gfx.ColorType = 0x3a3a3a;
    hidden const GRAPH_FILL_COLOR as Gfx.ColorType = 0x1c3320;
    hidden const GRAPH_CORNER_RADIUS as Lang.Number = 8;

    hidden function drawGraph(dc as Gfx.Dc, x as Lang.Number, y as Lang.Number, w as Lang.Number, h as Lang.Number) as Void {
        dc.setColor(GRAPH_CARD_COLOR, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, GRAPH_CORNER_RADIUS);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, h, GRAPH_CORNER_RADIUS);

        var count = recorder.getHistoryCount();
        if (count < 2) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, y + h / 2, Gfx.FONT_XTINY, "Waiting for data...", Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            return;
        }

        var history = recorder.getHistory();
        var range = graphColorRange(history, count);
        var colorMin = range[0];
        var colorMax = range[1];
        var heightMax = colorMax * 1.15;
        if (heightMax <= 0.0) { heightMax = 0.01; }

        dc.setColor(GRAPH_GRID_COLOR, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(x, y + (h * 0.25).toNumber(), x + w, y + (h * 0.25).toNumber());
        dc.drawLine(x, y + (h * 0.50).toNumber(), x + w, y + (h * 0.50).toNumber());
        dc.drawLine(x, y + (h * 0.75).toNumber(), x + w, y + (h * 0.75).toNumber());

        var xs = new [count] as Lang.Array<Lang.Number>;
        var ys = new [count] as Lang.Array<Lang.Number>;
        for (var i = 0; i < count; i += 1) {
            xs[i] = x + (i * w) / (count - 1);
            var py = y + h - ((history[i] / heightMax) * h).toNumber();
            if (py < y) { py = y; }
            ys[i] = py;
        }

        var fillPoints = new [count + 2] as Lang.Array<Gfx.Point2D>;
        fillPoints[0] = [xs[0], y + h];
        for (var i = 0; i < count; i += 1) {
            fillPoints[i + 1] = [xs[i], ys[i]];
        }
        fillPoints[count + 1] = [xs[count - 1], y + h];
        dc.setColor(GRAPH_FILL_COLOR, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(fillPoints);

        dc.setPenWidth(2);
        for (var i = 1; i < count; i += 1) {
            var avgValue = (history[i - 1] + history[i]) / 2.0;
            dc.setColor(roughnessColor(avgValue, colorMin, colorMax), Gfx.COLOR_TRANSPARENT);
            dc.drawLine(xs[i - 1], ys[i - 1], xs[i], ys[i]);
        }
        dc.setPenWidth(1);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(xs[count - 1], ys[count - 1], 3);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x + 4, y + 1, Gfx.FONT_XTINY, heightMax.format("%.2f") + "g", Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
    }

    // 5th/95th percentile of the visible history, used both as the
    // color-gradient bounds and (via the caller adding headroom) the
    // graph's vertical scale. Falls back to plain min/max when there's
    // too little data for percentiles to be meaningful yet, matching how
    // the map/web viewer handle the same situation.
    hidden function graphColorRange(history as Lang.Array<Lang.Float>, count as Lang.Number) as Lang.Array<Lang.Float> {
        if (count < 5) {
            var minValue = history[0];
            var maxValue = history[0];
            for (var i = 1; i < count; i += 1) {
                if (history[i] < minValue) { minValue = history[i]; }
                if (history[i] > maxValue) { maxValue = history[i]; }
            }
            return [minValue, maxValue] as Lang.Array<Lang.Float>;
        }

        var sorted = new [count] as Lang.Array<Lang.Float>;
        for (var i = 0; i < count; i += 1) {
            sorted[i] = history[i];
        }
        insertionSort(sorted);

        var p5Index = (count * 0.05).toNumber();
        var p95Index = (count * 0.95).toNumber();
        if (p95Index >= count) { p95Index = count - 1; }

        var p5 = sorted[p5Index];
        var p95 = sorted[p95Index];
        if (p95 <= p5) { p95 = sorted[count - 1]; }
        return [p5, p95] as Lang.Array<Lang.Float>;
    }

    // Array.sort() needs API Level 5.0.0, which the Edge 1030 Plus
    // doesn't support (same as RoadQualityMapView's copy of this) -
    // plain insertion sort instead, fine for the at most 120 elements
    // the history buffer ever holds.
    hidden function insertionSort(values as Lang.Array<Lang.Float>) as Void {
        for (var i = 1; i < values.size(); i += 1) {
            var key = values[i];
            var j = i - 1;
            while (j >= 0 && values[j] > key) {
                values[j + 1] = values[j];
                j -= 1;
            }
            values[j + 1] = key;
        }
    }

    // Same green (smooth) -> yellow -> red (rough) gradient as the map
    // screen and docs/ web viewer's roughnessColor(). Graphics.ColorType
    // is just a packed 0xRRGGBB Number - built with bit shifts rather
    // than Graphics.createColor(), which needs API Level 4.0.0 and isn't
    // supported on the Edge 1030 Plus.
    hidden function roughnessColor(value as Lang.Float, minValue as Lang.Float, maxValue as Lang.Float) as Gfx.ColorType {
        var t = 0.0;
        if (maxValue > minValue) {
            t = (value - minValue) / (maxValue - minValue);
        }
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }

        var r = 255;
        var g = 255;
        if (t < 0.5) {
            r = (255 * (t / 0.5)).toNumber();
        } else {
            g = (255 * (1 - (t - 0.5) / 0.5)).toNumber();
        }
        return (r << 16) | (g << 8);
    }

}
