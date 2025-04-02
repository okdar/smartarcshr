/*
    This file is part of SmartArcs HR watch face.
    https://github.com/okdar/smartarcshr

    SmartArcs HR is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SmartArcs HR is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with SmartArcs HR. If not, see <https://www.gnu.org/licenses/gpl.html>.
*/

using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Position;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
//using Toybox.UserProfile;
using Toybox.WatchUi;

class SmartArcsHrView extends WatchUi.WatchFace {

    //TRYING TO KEEP AS MUCH PRE-COMPUTED VALUES AS POSSIBLE IN MEMORY TO SAVE CPU UTILIZATION
    //AND HOPEFULLY PROLONG BATTERY LIFE. PRE-COMPUTED VARIABLES DON'T NEED TO BE COMPUTED
    //AGAIN AND AGAIN ON EACH SCREEN UPDATE. THAT'S THE REASON FOR LONG LIST OF GLOBAL VARIABLES.

    //global variables
    var isAwake = false;
    var partialUpdatesAllowed = false;
    var hasHeartRateHistory = false;
    var heartRateNumberOfSamples = 0;
    var fullScreenRefresh;
    var offscreenBuffer;
    var offSettingFlag = -999;
    var font;
    var lastMeasuredHR;
    var deviceSettings;
    var powerSaverDrawn = false;
    var sunArcsOffset;

    //global variables for pre-computation
    var screenWidth;
    var screenRadius;
    var screenResolutionRatio;
    var ticks;
    var hourHandLength;
    var minuteHandLength;
    var handsTailLength;
    var hrTextDimension;
    var halfHRTextWidth;
    var startPowerSaverMin;
    var endPowerSaverMin;
    var powerSaverIconRatio;
	var sunriseStartAngle = 0;
	var sunriseEndAngle = 0;
	var sunsetStartAngle = 0;
	var sunsetEndAngle = 0;
	var locationLatitude;
	var locationLongitude;
    var dateAt6Y;
    var dateInfo;
    // var genericZoneInfo;

    //user settings
    var bgColor;
    var handsColor;
    var handsOutlineColor;
    var hourHandWidth;
    var minuteHandWidth;
    var battery100Color;
    var battery30Color;
    var battery15Color;
    var notificationColor;
    var bluetoothColor;
    var dndColor;
    var alarmColor;
    var dateColor;
    var ticksColor;
    var ticks1MinWidth;
    var ticks5MinWidth;
    var ticks15MinWidth;
    var oneColor;
    var handsOnTop;
    var showBatteryIndicator;
    var dateFormat;
    var hrColor;
    var hrRefreshInterval;
    var graphBordersColor;
    var graphLegendColor;
    var graphLineWidth;
    var graphBgColor;
    var graphStyle;
    var powerSaver;
    var powerSaverRefreshInterval;
    var powerSaverIconColor;
    var sunriseColor;
    var sunsetColor;

    enum { // graph style
        LINE = 1,
        AREA = 2
    }

    function initialize() {
        WatchFace.initialize();
    }

    //load resources here
    function onLayout(dc) {
        //if this device supports BufferedBitmap, allocate the buffers we use for drawing
        if (Toybox.Graphics has :createBufferedBitmap) {
            // get() used to return resource as Graphics.BufferedBitmap
            //Allocate a full screen size buffer to draw the background image of the watchface.
            offscreenBuffer = Toybox.Graphics.createBufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            }).get();
        } else if (Toybox.Graphics has :BufferedBitmap) {
            //If this device supports BufferedBitmap, allocate the buffers we use for drawing
            //Allocate a full screen size buffer to draw the background image of the watchface.
            offscreenBuffer = new Toybox.Graphics.BufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
        } else {
            offscreenBuffer = null;
        }

        partialUpdatesAllowed = (Toybox.WatchUi.WatchFace has :onPartialUpdate);

        if (Toybox has :SensorHistory) {
            hasHeartRateHistory = Toybox.SensorHistory has :getHeartRateHistory;
        }

        screenWidth = dc.getWidth();
        screenRadius = screenWidth / 2;
        //TINY font for screen resolution 240 and lower, SMALL for higher resolution
        if (screenRadius <= 120) {
            font = Graphics.FONT_TINY;
        } else {
            font = Graphics.FONT_SMALL;
        }
        hrTextDimension = dc.getTextDimensions("888", font); //to compute correct clip boundaries

        loadUserSettings();
        fullScreenRefresh = true;
    }

    //called when this View is brought to the foreground. Restore
    //the state of this View and prepare it to be shown. This includes
    //loading resources into memory.
    function onShow() {
    }

    //update the view
    function onUpdate(dc) {
        var clockTime = System.getClockTime();

		//refresh whole screen before drawing power saver icon
        if (powerSaverDrawn && shouldPowerSave()) {
            //should be screen refreshed in given intervals?
            if (powerSaverRefreshInterval == offSettingFlag || !(clockTime.min % powerSaverRefreshInterval == 0)) {
                return;
            }
        }

        powerSaverDrawn = false;

        deviceSettings = System.getDeviceSettings();

		if (clockTime.min == 0) {
            //recompute sunrise/sunset constants every hour - to address new location when traveling	
			computeSunConstants();
		}

        //we always want to refresh the full screen when we get a regular onUpdate call.
        fullScreenRefresh = true;

        var targetDc = null;
        if (offscreenBuffer != null) {
            //if we have an offscreen buffer that we are using to draw the background,
            //set the draw context of that buffer as our target.
            targetDc = offscreenBuffer.getDc();
            dc.clearClip();
        } else {
            targetDc = dc;
        }

        //clear the screen
        targetDc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        targetDc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        if (showBatteryIndicator) {
            var batStat = System.getSystemStats().battery;
            if (oneColor != offSettingFlag) {
                drawSmartArc(targetDc, oneColor, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
            } else {
                if (batStat > 30) {
                    drawSmartArc(targetDc, battery100Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                    drawSmartArc(targetDc, battery30Color, Graphics.ARC_CLOCKWISE, 180, 153);
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 166.5);
                } else if (batStat <= 30 && batStat > 15) {
                    drawSmartArc(targetDc, battery30Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 166.5);
                } else {
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                }
            }
        }

        var itemCount = deviceSettings.notificationCount;
        if (notificationColor != offSettingFlag && itemCount > 0) {
            if (itemCount < 11) {
                drawSmartArc(targetDc, notificationColor, Graphics.ARC_CLOCKWISE, 90, 90 - 30 - ((itemCount - 1) * 6));
            } else {
                drawSmartArc(targetDc, notificationColor, Graphics.ARC_CLOCKWISE, 90, 0);
            }
        }

        if (bluetoothColor != offSettingFlag && deviceSettings.phoneConnected) {
            drawSmartArc(targetDc, bluetoothColor, Graphics.ARC_CLOCKWISE, 0, -30);
        }

        if (dndColor != offSettingFlag && deviceSettings.doNotDisturb) {
            drawSmartArc(targetDc, dndColor, Graphics.ARC_COUNTER_CLOCKWISE, 270, -60);
        }

        itemCount = deviceSettings.alarmCount;
        if (alarmColor != offSettingFlag && itemCount > 0) {
            if (itemCount < 11) {
                drawSmartArc(targetDc, alarmColor, Graphics.ARC_CLOCKWISE, 270, 270 - 30 - ((itemCount - 1) * 6));
            } else {
                drawSmartArc(targetDc, alarmColor, Graphics.ARC_CLOCKWISE, 270, 0);
            }
        }

        if (locationLatitude != offSettingFlag) {
    	    drawSun(targetDc);
        }

        if (ticks != null) {
            drawTicks(targetDc);
        }

        if (!handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        if (hasHeartRateHistory) {
            drawGraph(targetDc, SensorHistory.getHeartRateHistory({}), 5, heartRateNumberOfSamples);
        }

        if (dateColor != offSettingFlag) {
            drawDate(targetDc);
        }

        if (handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

        if (shouldPowerSave()) {
            drawPowerSaverIcon(dc);
            return;
        }

        if (partialUpdatesAllowed && hrColor != offSettingFlag) {
            onPartialUpdate(dc);
        }

        fullScreenRefresh = false;
    }

    //called when this View is removed from the screen. Save the state
    //of this View here. This includes freeing resources from memory.
    function onHide() {
    }

    //the user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() {
        isAwake = true;
    }

    //terminate any active timers and prepare for slow updates.
    function onEnterSleep() {
        isAwake = false;
        requestUpdate();
    }

    function loadUserSettings() {
        var app = Application.getApp();

        oneColor = app.getProperty("oneColor");
        if (oneColor == offSettingFlag) {
            battery100Color = app.getProperty("battery100Color");
            battery30Color = app.getProperty("battery30Color");
            battery15Color = app.getProperty("battery15Color");
            notificationColor = app.getProperty("notificationColor");
            bluetoothColor = app.getProperty("bluetoothColor");
            dndColor = app.getProperty("dndColor");
            alarmColor = app.getProperty("alarmColor");
            sunriseColor = app.getProperty("sunriseColor");
			sunsetColor = app.getProperty("sunsetColor");
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
            sunriseColor = oneColor;
			sunsetColor = oneColor;
        }
        bgColor = app.getProperty("bgColor");
        ticksColor = app.getProperty("ticksColor");
        if (ticksColor != offSettingFlag) {
            ticks1MinWidth = app.getProperty("ticks1MinWidth");
            ticks5MinWidth = app.getProperty("ticks5MinWidth");
            ticks15MinWidth = app.getProperty("ticks15MinWidth");
        }
        handsColor = app.getProperty("handsColor");
        handsOutlineColor = app.getProperty("handsOutlineColor");
        hourHandWidth = app.getProperty("hourHandWidth");
        minuteHandWidth = app.getProperty("minuteHandWidth");
        dateColor = app.getProperty("dateColor");
        hrColor = app.getProperty("hrColor");

        if (dateColor != offSettingFlag) {
            dateFormat = app.getProperty("dateFormat");
        }

        if (hrColor != offSettingFlag) {
            hrRefreshInterval = app.getProperty("hrRefreshInterval");
        }

        handsOnTop = app.getProperty("handsOnTop");

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        graphBordersColor = app.getProperty("graphBordersColor");
        graphLineWidth = app.getProperty("graphLineWidth");
        graphBgColor = app.getProperty("graphBgColor");
        graphStyle = app.getProperty("graphStyle");

        var power = app.getProperty("powerSaver");
		powerSaverRefreshInterval = app.getProperty("powerSaverRefreshInterval");
		powerSaverIconColor = app.getProperty("powerSaverIconColor");
        if (power == 1) {
        	powerSaver = false;
    	} else {
    		powerSaver = true;
            var powerSaverBeginning;
            var powerSaverEnd;
            if (power == 2) {
                powerSaverBeginning = app.getProperty("powerSaverBeginning");
                powerSaverEnd = app.getProperty("powerSaverEnd");
            } else {
                powerSaverBeginning = "00:00";
                powerSaverEnd = "23:59";
                powerSaverRefreshInterval = -999;
            }
            startPowerSaverMin = parsePowerSaverTime(powerSaverBeginning);
            if (startPowerSaverMin == -1) {
                powerSaver = false;
            } else {
                endPowerSaverMin = parsePowerSaverTime(powerSaverEnd);
                if (endPowerSaverMin == -1) {
                    powerSaver = false;
                }
            }
        }
		
		locationLatitude = app.getProperty("locationLatitude");
		locationLongitude = app.getProperty("locationLongitude");

        //ensure that screen will be refreshed when settings are changed 
    	powerSaverDrawn = false;
        
        computeConstants();
		computeSunConstants();
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants() {
        // genericZoneInfo = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        // System.print(genericZoneInfo);

        //computes hand lenght for watches with different screen resolution than 260x260
        screenResolutionRatio = screenRadius / 130.0; //130.0 = half of vivoactive4 resolution; used for coordinates recalculation
        hourHandLength = recalculateCoordinate(60);
        minuteHandLength = recalculateCoordinate(90);
        handsTailLength = recalculateCoordinate(15);
        
        if (powerSaverRefreshInterval == offSettingFlag) {
            powerSaverIconRatio = 1.0; //big icon
        } else {
            powerSaverIconRatio = 0.6; //small icon
        }

        if (!((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0))) {
            //array of ticks coordinates
            computeTicks();
        }

        halfHRTextWidth = hrTextDimension[0] / 2;

        heartRateNumberOfSamples = hasHeartRateHistory ? countSamples(SensorHistory.getHeartRateHistory({})) : 0;

        dateAt6Y = screenWidth - Graphics.getFontHeight(font) - recalculateCoordinate(35);
        dateInfo = Gregorian.info(Time.today(), Time.FORMAT_MEDIUM);
    }

    function parsePowerSaverTime(time) {
        var pos = time.find(":");
        if (pos != null) {
            var hour = time.substring(0, pos).toNumber();
            var min = time.substring(pos + 1, time.length()).toNumber();
            if (hour != null && min != null) {
                return (hour * 60) + min;
            } else {
                return -1;
            }
        } else {
            return -1;
        }
    }

    function computeTicks() {
        var angle;
        ticks = new [16];
        //to save the memory compute only a quarter of the ticks, the rest will be mirrored.
        //I believe it will still save some CPU utilization
        for (var i = 0; i < 16; i++) {
            angle = i * Math.PI * 2 / 60.0;
            if ((i % 15) == 0) { //quarter tick
                if (ticks15MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, recalculateCoordinate(20), ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, recalculateCoordinate(20), ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, recalculateCoordinate(10), ticks1MinWidth);
            }
        }
    }

    function computeTickRectangle(angle, length, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, screenRadius], [-halfWidth, screenRadius - length], [halfWidth, screenRadius - length], [halfWidth, screenRadius]];
        return computeRectangle(coords, angle);
    }

    function computeRectangle(coords, angle) {
        var rect = new [4];
        var x;
        var y;
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        //transform coordinates
        for (var i = 0; i < 4; i++) {
            x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;
            rect[i] = [screenRadius + x, screenRadius + y];
        }

        return rect;
    }

    function drawSmartArc(dc, color, arcDirection, startAngle, endAngle) {
        dc.setPenWidth(recalculateCoordinate(10));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(5), arcDirection, startAngle, endAngle);
    }

    function drawTicks(dc) {
        var coord = new [4];
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 16; i++) {
        	//30-45 ticks
            if (ticks[i] != null) {
                dc.fillPolygon(ticks[i]);
            }

            //mirror pre-computed ticks
            if (i >= 0 && i <= 15 && ticks[i] != null) {
            	//15-30 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], ticks[i][j][1]];
                }
                dc.fillPolygon(coord);

				//45-60 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [ticks[i][j][0], screenWidth - ticks[i][j][1]];
                }
                dc.fillPolygon(coord);

				//0-15 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], screenWidth - ticks[i][j][1]];
                }
                dc.fillPolygon(coord);
            }
        }
    }

    function drawHands(dc, clockTime) {
        var hourAngle, minAngle;

        //draw hour hand
        hourAngle = ((clockTime.hour % 12) * 60.0) + clockTime.min;
        hourAngle = hourAngle / (12 * 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + recalculateCoordinate(2), handsTailLength + recalculateCoordinate(2), hourHandWidth + recalculateCoordinate(4)));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + recalculateCoordinate(2), handsTailLength + recalculateCoordinate(2), minuteHandWidth + recalculateCoordinate(4)));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        dc.setPenWidth(bulletRadius);
        dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(screenRadius, screenRadius, bulletRadius + recalculateCoordinate(2));
    }

    function drawHand(dc, color, coords) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(coords);
    }

    function computeHandRectangle(angle, handLength, tailLength, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, tailLength], [-halfWidth, -handLength], [halfWidth, -handLength], [halfWidth, tailLength]];
        return computeRectangle(coords, angle);
    }

    //Handle the partial update event
    function onPartialUpdate(dc) {
		//refresh whole screen before drawing power saver icon
        if (powerSaverDrawn && shouldPowerSave()) {
    		return;
    	}

        powerSaverDrawn = false;

        var refreshHR = false;
        var clockSeconds = System.getClockTime().sec;

        //should be HR refreshed?
        if (hrColor != offSettingFlag) {
            if (hrRefreshInterval == 1) {
                refreshHR = true;
            } else if (clockSeconds % hrRefreshInterval == 0) {
                refreshHR = true;
            }
        }

        //if we're not doing a full screen refresh we need to re-draw the background
        //before drawing the updated second hand position. Note this will only re-draw
        //the background in the area specified by the previously computed clipping region.
        if(!fullScreenRefresh) {
            drawBackground(dc);
        }

        //draw HR
        if (hrColor != offSettingFlag) {
            drawHR(dc, refreshHR);
        }
        
        if (shouldPowerSave()) {
            requestUpdate();
        }
    }

    //Draw the watch face background
    //onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    //to the main display.
    //onPartialUpdate uses this to blank the second hand from the previous
    //second before outputing the new one.
    function drawBackground(dc) {
        //If we have an offscreen buffer that has been written to
        //draw it to the screen.
        if( null != offscreenBuffer ) {
            dc.drawBitmap(0, 0, offscreenBuffer);
        }
    }

    //Compute a bounding box from the passed in points
    function getBoundingBox(points) {
        var min = [9999,9999];
        var max = [0,0];

        for (var i = 0; i < points.size(); ++i) {
            if(points[i][0] < min[0]) {
                min[0] = points[i][0];
            }
            if(points[i][1] < min[1]) {
                min[1] = points[i][1];
            }
            if(points[i][0] > max[0]) {
                max[0] = points[i][0];
            }
            if(points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }

        return [min, max];
    }

    //coordinates are optimized for 260x260 resolution (vivoactive4)
    //this method recalculates coordinates for watches with different resolution
    function recalculateCoordinate(coordinate) {
        return (coordinate * screenResolutionRatio).toNumber();
    }

    function drawHR(dc, refreshHR) {
        var hr = 0;
        var hrText;
        var activityInfo;

        if (refreshHR) {
            activityInfo = Activity.getActivityInfo();
            if (activityInfo != null) {
                hr = activityInfo.currentHeartRate;
                lastMeasuredHR = hr;
            }
        } else {
            hr = lastMeasuredHR;
        }

        if (hr == null || hr == 0) {
            hrText = "";
        } else {
            hrText = hr.format("%i");
        }

        dc.setClip(screenRadius - halfHRTextWidth, recalculateCoordinate(30), hrTextDimension[0], hrTextDimension[1]);

        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        //debug rectangle
        //dc.drawRectangle(screenRadius - halfHRTextWidth, recalculateCoordinate(30), hrTextDimension[0], hrTextDimension[1]);
        dc.drawText(screenRadius, recalculateCoordinate(30), font, hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawGraph(dc, iterator, minimalRange, numberOfSamples) {
        var yPos = 77;

        var minVal = iterator.getMin();
        var maxVal = iterator.getMax();
        if (minVal == null || maxVal == null || numberOfSamples == 0) {
            return;
        }

        var graphTextHeight = dc.getTextDimensions("8", Graphics.FONT_XTINY)[1]; //font height

        var leftX = recalculateCoordinate(40); //40 pixels from screen border
        var topY = recalculateCoordinate(yPos) - 1;
        var graphHeight = recalculateCoordinate(screenRadius - 90) * 2;

        var range = maxVal - minVal;
        if (range < minimalRange) {
            var avg = (minVal + maxVal) / 2.0;
            minVal = avg - (minimalRange / 2.0);
            maxVal = avg + (minimalRange / 2.0);
            range = minimalRange;
        }

        var minValStr = minVal.format("%.0f");
        var maxValStr = maxVal.format("%.0f");

        //draw min and max values
        dc.setColor(graphBordersColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(8), topY - graphTextHeight + 3, Graphics.FONT_XTINY, maxValStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(leftX + recalculateCoordinate(8), recalculateCoordinate(yPos) + graphHeight - 2, Graphics.FONT_XTINY, minValStr, Graphics.TEXT_JUSTIFY_LEFT);
        //draw rectangle
        dc.setColor(graphBgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(leftX, recalculateCoordinate(yPos), screenWidth - (2 * leftX) + 1, graphHeight); // for graph
        dc.fillRectangle(leftX, recalculateCoordinate(yPos + 15) + graphHeight, screenWidth - (2 * leftX) + 1, graphTextHeight); // for legend

        //get latest sample
        var item = iterator.next();
        var counter = 1; //used only for 180 samples history
        var value = null;
        var x1 = (screenWidth - leftX).toNumber();
        var y1 = null;
        var x2, y2;
        dc.setPenWidth(graphLineWidth);
        if (item != null) {
            value = item.data;
            if (value != null) {
                y1 = (topY + graphHeight + 1) - ((recalculateCoordinate(value) / 1.0) - recalculateCoordinate(minVal)) / recalculateCoordinate(range) * graphHeight;

                dc.setColor(getGraphLineColor(value), Graphics.COLOR_TRANSPARENT);
                if (graphStyle == AREA) {
                    dc.drawLine(x1, y1, x1, recalculateCoordinate(yPos) + graphHeight);
                } else {
                    dc.drawPoint(x1, y1);
                }
            }
        } else {
            //no samples
            return;
        }

        var times = 0; //how many times is number of samples bigger than graph width in pixels
        var rest = numberOfSamples;
        var smp = (screenWidth - (2 * leftX)).toNumber();
        while (rest > smp) {
            times++;
            rest -= smp;
        }
        var skipPossition = (numberOfSamples / rest) * times;

        item = iterator.next();
        counter++;
        if (item != null) {
            var timestamp = Toybox.Time.Gregorian.info(item.when, Time.FORMAT_SHORT);
            if (times > 1 && timestamp.min % times == 1) {
                //prevent "jumping" graph (in one minute are shown even samples, in another odd samples and so on)
                counter--;            
            }
        }
        while (item != null) {
            if (times == 1 && counter % skipPossition == 0) {
                //skip each 'skipPosition' position sample to display only graph width in pixels samples because of screen size
                item = iterator.next();
                counter++;
                continue;
            }
            if (times > 1) {                
                if (counter % skipPossition == 1) {
                    //skip each 'skipPosition' positon sample to display only graph width in pixels samples because of screen size
                    item = iterator.next();
                    counter++;
                    continue;
                }
                if (counter % times == 0) {
                    //many samples, skip every 'times' position sample
                    item = iterator.next();
                    counter++;
                    continue;
                }
            }

            value = item.data;
            x2 = x1 - 1;
            if (value != null) {
                dc.setColor(getGraphLineColor(value), Graphics.COLOR_TRANSPARENT);
                y2 = (topY + graphHeight + 1) - ((recalculateCoordinate(value) / 1.0) - recalculateCoordinate(minVal)) / recalculateCoordinate(range) * graphHeight;
                if (graphStyle == AREA) {
                    dc.drawLine(x2, y2, x2, recalculateCoordinate(yPos) + graphHeight);
                } else if (y1 != null) {
                    dc.drawLine(x2, y2, x1, y1);
                } else {
                    dc.drawPoint(x2, y2);
                }
                y1 = y2;
            } else {
                y1 = null;
            }
            x1 = x2;

            item = iterator.next();
            counter++;
        }

        //draw graph borders
        if (graphBordersColor != offSettingFlag) {
            var maxX = leftX + (dc.getTextDimensions(maxValStr, Graphics.FONT_XTINY))[0] + 5;
            var minX = leftX + (dc.getTextDimensions(minValStr, Graphics.FONT_XTINY))[0] + 5;
            dc.setColor(graphBordersColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(leftX, topY, leftX + recalculateCoordinate(6), topY);
            dc.drawLine(leftX, recalculateCoordinate(yPos) + graphHeight, leftX + recalculateCoordinate(6), recalculateCoordinate(yPos) + graphHeight);
            dc.drawLine(maxX + recalculateCoordinate(5), topY, screenWidth - leftX, topY);
            dc.drawLine(minX + recalculateCoordinate(5), recalculateCoordinate(yPos) + graphHeight, screenWidth - leftX, recalculateCoordinate(yPos) + graphHeight);

            var x;
            for (var i = 0; i <= 6; i++) {
                x = leftX + (i * ((screenWidth - (2 * leftX)) / 6 ));
                dc.drawLine(x, topY, x, topY + recalculateCoordinate(5 + 1));
                dc.drawLine(x, recalculateCoordinate(yPos) + graphHeight - recalculateCoordinate(5), x, recalculateCoordinate(yPos) + graphHeight + 1);
            }
        }

        leftX += recalculateCoordinate(8);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, "60", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(20), recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, "70", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(40), recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, "80", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(0xffff00, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(60), recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, "90", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(80), recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, "100", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(108), recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, "110", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + recalculateCoordinate(136), recalculateCoordinate(yPos + 15) + graphHeight, Graphics.FONT_XTINY, ">110", Graphics.TEXT_JUSTIFY_LEFT);
    }

    function getGraphLineColor(value) {
        var color = Graphics.COLOR_LT_GRAY; //HR<=60
        if (value > 60 && value <= 70) {
            color = Graphics.COLOR_BLUE;
        } else if (value > 70 && value <= 80) {
            color = Graphics.COLOR_GREEN;
        } else if (value > 80 && value <= 90) {
            color = 0xffff00; //true yellow
        } else if (value > 90 && value <= 100) {
            color = Graphics.COLOR_PINK;
        } else if (value > 100 && value <= 110) {
            color = Graphics.COLOR_ORANGE;
        } else if (value > 110) {
            color = Graphics.COLOR_RED;
        }

        return color;
    }

    function countSamples(iterator) {
        var count = 0;
        while (iterator.next() != null) {
            count++;
        }

        return count;
    }

    function drawDate(dc) {
        var dateString = "";
        switch (dateFormat) {
            case 0: dateString = dateInfo.day;
                    break;
            case 1: dateString = Lang.format("$1$ $2$", [dateInfo.day_of_week.substring(0, 3), dateInfo.day]);
                    break;
            case 2: dateString = Lang.format("$1$ $2$", [dateInfo.day, dateInfo.day_of_week.substring(0, 3)]);
                    break;
            case 3: dateString = Lang.format("$1$ $2$", [dateInfo.day, dateInfo.month.substring(0, 3)]);
                    break;
            case 4: dateString = Lang.format("$1$ $2$", [dateInfo.month.substring(0, 3), dateInfo.day]);
                    break;
        }
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenRadius, dateAt6Y, font, dateString, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function shouldPowerSave() {
        if (powerSaver && !isAwake) {
        var refreshDisplay = true;
        var time = System.getClockTime();
        var timeMinOfDay = (time.hour * 60) + time.min;
        
        if (startPowerSaverMin <= endPowerSaverMin) {
        	if ((startPowerSaverMin <= timeMinOfDay) && (timeMinOfDay < endPowerSaverMin)) {
        		refreshDisplay = false;
        	}
        } else {
        	if ((startPowerSaverMin <= timeMinOfDay) || (timeMinOfDay < endPowerSaverMin)) {
        		refreshDisplay = false;
        	}        
        }
        return !refreshDisplay;
        } else {
            return false;
        }
    }

    function drawPowerSaverIcon(dc) {
        dc.setColor(handsColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, recalculateCoordinate(45) * powerSaverIconRatio);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, recalculateCoordinate(40) * powerSaverIconRatio);
        dc.setColor(handsColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(screenRadius - (recalculateCoordinate(13) * powerSaverIconRatio), screenRadius - (recalculateCoordinate(23) * powerSaverIconRatio), recalculateCoordinate(26) * powerSaverIconRatio, recalculateCoordinate(51) * powerSaverIconRatio);
        dc.fillRectangle(screenRadius - (recalculateCoordinate(4) * powerSaverIconRatio), screenRadius - (recalculateCoordinate(27) * powerSaverIconRatio), recalculateCoordinate(8) * powerSaverIconRatio, recalculateCoordinate(5) * powerSaverIconRatio);
        if (oneColor == offSettingFlag) {
            dc.setColor(powerSaverIconColor, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(oneColor, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(screenRadius - (recalculateCoordinate(10) * powerSaverIconRatio), screenRadius - (recalculateCoordinate(20) * powerSaverIconRatio), recalculateCoordinate(20) * powerSaverIconRatio, recalculateCoordinate(45) * powerSaverIconRatio);

        powerSaverDrawn = true;
    }

	function computeSunConstants() {
    	var posInfo = Toybox.Position.getInfo();
    	if (posInfo != null && posInfo.position != null) {
	    	var sc = new SunCalc();
	    	var time_now = Time.now();    	
	    	var loc = posInfo.position.toRadians();
    		var hasLocation = (loc[0].format("%.2f").equals("3.14") && loc[1].format("%.2f").equals("3.14")) || (loc[0] == 0 && loc[1] == 0) ? false : true;

	    	if (!hasLocation && locationLatitude != offSettingFlag) {
	    		loc[0] = locationLatitude;
	    		loc[1] = locationLongitude;
	    	}

	    	if (hasLocation) {
				Application.getApp().setProperty("locationLatitude", loc[0]);
				Application.getApp().setProperty("locationLongitude", loc[1]);
				locationLatitude = loc[0];
				locationLongitude = loc[1];
			}
			
	        sunriseStartAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.DAWN));	        
	        sunriseEndAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.SUNRISE));
	        sunsetStartAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.SUNSET));
	        sunsetEndAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.DUSK));

            if (((sunriseStartAngle < sunsetStartAngle) && (sunriseStartAngle > sunsetEndAngle)) ||
                    ((sunriseEndAngle < sunsetStartAngle) && (sunriseEndAngle > sunsetEndAngle)) ||
                    ((sunsetStartAngle < sunriseStartAngle) && (sunsetStartAngle > sunriseEndAngle)) ||
                    ((sunsetEndAngle < sunriseStartAngle) && (sunsetEndAngle > sunriseEndAngle))) {
                sunArcsOffset = recalculateCoordinate(10);
            } else {
                sunArcsOffset = recalculateCoordinate(12);
            }
        }
	}

	function computeSunAngle(time) {
        var timeInfo = Time.Gregorian.info(time, Time.FORMAT_SHORT);       
        var angle = ((timeInfo.hour % 12) * 60.0) + timeInfo.min;
        angle = angle / (12 * 60.0) * Math.PI * 2;
        return Math.toDegrees(-angle + Math.PI/2);	
	}

	function drawSun(dc) {
        dc.setPenWidth(1);

        var arcWidth = recalculateCoordinate(9);
        if (sunArcsOffset == recalculateCoordinate(10)) {
            arcWidth = recalculateCoordinate(7);
        }

        //draw sunrise
        if (sunriseColor != offSettingFlag) {
	        if (sunriseStartAngle > sunriseEndAngle) {
    	        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
                var step = (sunriseStartAngle - sunriseEndAngle) / arcWidth;
                for (var i = 0; i < arcWidth; i++) {
                    if (sunArcsOffset == recalculateCoordinate(10)) {
				        dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(20) + i, Graphics.ARC_CLOCKWISE, sunriseStartAngle - (step * i), sunriseEndAngle);
                    } else {
				        dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(12) - i, Graphics.ARC_CLOCKWISE, sunriseStartAngle - (step * i), sunriseEndAngle);
                    }
                }
			} else {
		        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
    			dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(17), Graphics.ARC_COUNTER_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
			}
		}

        //draw sunset
        if (sunsetColor != offSettingFlag) {
	        if (sunsetStartAngle > sunsetEndAngle) {
    	        dc.setColor(sunsetColor, Graphics.COLOR_TRANSPARENT);
                var step = (sunsetStartAngle - sunsetEndAngle) / arcWidth;
                for (var i = 0; i < arcWidth; i++) {
				    dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset - i, Graphics.ARC_CLOCKWISE, sunsetStartAngle, sunsetEndAngle + (step * i));
                }
			} else {
    	        dc.setColor(sunsetColor, Graphics.COLOR_TRANSPARENT);
				dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset, Graphics.ARC_COUNTER_CLOCKWISE, sunsetStartAngle, sunsetEndAngle);
			}
		}
	}

}
