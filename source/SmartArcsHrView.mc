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
    var lastPhoneConnectedTime;

    var hrCache = null;
    var hrCacheHead = 0;
    var hrCacheSize = 180;
    var updated = null;
    var minHr;
    var maxHr;
    var lastOddMinHr = null;

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
	var sunriseStartAngle = 0;
	var sunriseEndAngle = 0;
	var sunsetStartAngle = 0;
	var sunsetEndAngle = 0;
	var locationLatitude;
	var locationLongitude;
    var dateAt6Y;
    var graphFontHeight;

    //pre-computed recalculateCoordinate(N) constants (rcN = N pixels scaled to screen resolution)
    var rc2;
    var rc4;
    var rc5;
    var rc6;
    var rc7;
    var rc8;
    var rc9;
    var rc10;
    var rc12;
    var rc16;
    var rc17;
    var rc20;
    var rc25;
    var rc30;
    var rc40;
    var rc60;
    var rc76;
    var rc80;
    var rc108;
    var rc136;

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
    var showBatteryIndicator;
    var dateFormat;
    var hrColor;
    var hrRefreshInterval;
    var graphBordersColor;
    var graphLineWidth;
    var graphBgColor;
    var graph60Color;
    var graph70Color;
    var graph80Color;
    var graph90Color;
    var graph100Color;
    var graph110Color;
    var graph120Color;
    var graphStyle;
    var powerSaver;
    var powerSaverRefreshInterval;
    var sunriseColor;
    var sunsetColor;
    var showLostAndFound;
    var phone;
    var email;

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
        graphFontHeight = dc.getTextDimensions("8", Graphics.FONT_XTINY)[1];

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

        //cache HR values for graph
        updateHrCache(clockTime, Activity.getActivityInfo());

        deviceSettings = System.getDeviceSettings();
        if (deviceSettings.phoneConnected) {
            lastPhoneConnectedTime = Time.now();
            if (clockTime.min % 10 == 0) {
                Application.getApp().setProperty("lastPhoneConnectedTime", lastPhoneConnectedTime.value());
            }
        } else if (showLostAndFound != offSettingFlag &&
                    (lastPhoneConnectedTime == null || Time.now().subtract(lastPhoneConnectedTime).value() > showLostAndFound)) {
                //update power saver display
                var targetDc;
                if (offscreenBuffer != null) {
                    //if we have an offscreen buffer that we are using to draw the background,
                    //set the draw context of that buffer as our target.
                    targetDc = offscreenBuffer.getDc();
                    dc.clearClip();
                } else {
                    targetDc = dc;
                }

                drawLostAndFound(targetDc);

                //update screen
                drawBackground(dc);

                return;
        }
        
        //check power saver state
        if (shouldPowerSave()) {
            //if already in power saver mode, check if we need to refresh
            if (powerSaverDrawn) {
                //only refresh at specified intervals or if first time
                if (powerSaverRefreshInterval == offSettingFlag || !(clockTime.min % powerSaverRefreshInterval == 0)) {
                    //preserve current screen state
                    drawBackground(dc);
                    return;
                }
            }

            //update power saver display
            var targetDc;
            if (offscreenBuffer != null) {
                //if we have an offscreen buffer that we are using to draw the background,
                //set the draw context of that buffer as our target.
                targetDc = offscreenBuffer.getDc();
                dc.clearClip();
            } else {
                targetDc = dc;
            }

            //clear screen and draw minimal display
            targetDc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
            targetDc.fillCircle(screenRadius, screenRadius, screenRadius + 2);
            drawHands(targetDc, clockTime);

            //update screen
           drawBackground(dc);

            //update state
            powerSaverDrawn = true;
            return;
        }

        //regular update path
        powerSaverDrawn = false;

		if (clockTime.min == 0) {
            //recompute sunrise/sunset constants every hour - to address new location when traveling	
			computeSunConstants();
		}

        //we always want to refresh the full screen when we get a regular onUpdate call.
        fullScreenRefresh = true;

        var targetDc;
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

        if (hasHeartRateHistory && minHr != 0 && maxHr != 0) {
            drawHrGraph(targetDc, 5);
        }

        if (dateColor != offSettingFlag) {
            drawDate(targetDc);
        }

        drawHands(targetDc, clockTime);

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

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
        requestUpdate();
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

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        graphBordersColor = app.getProperty("graphBordersColor");
        graphLineWidth = app.getProperty("graphLineWidth");
        graphBgColor = app.getProperty("graphBgColor");
        graphStyle = app.getProperty("graphStyle");
        graph60Color = app.getProperty("graph60Color");
        graph70Color = app.getProperty("graph70Color");
        graph80Color = app.getProperty("graph80Color");
        graph90Color = app.getProperty("graph90Color");
        graph100Color = app.getProperty("graph100Color");
        graph110Color = app.getProperty("graph110Color");
        graph120Color = app.getProperty("graph120Color");

        var power = app.getProperty("powerSaver");
		powerSaverRefreshInterval = app.getProperty("powerSaverRefreshInterval");
        if (power == 1) {
        	powerSaver = false;
    	} else {
    		powerSaver = true;
            var powerSaverBeginning = app.getProperty("powerSaverBeginning");
            var powerSaverEnd = app.getProperty("powerSaverEnd");
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

        showLostAndFound = app.getProperty("showLostAndFound");
        if (showLostAndFound != offSettingFlag) {
            showLostAndFound *= 3600;
        }
        phone = app.getProperty("phone");
        email = app.getProperty("email");
        if (app.getProperty("lastPhoneConnectedTime") == -999) {
            lastPhoneConnectedTime = null;
        } else {
            lastPhoneConnectedTime = new Time.Moment(app.getProperty("lastPhoneConnectedTime"));
        }

        //ensure that screen will be refreshed when settings are changed 
    	powerSaverDrawn = false;
        
        computeConstants();
		computeSunConstants();
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants() {
        //computes hand lenght for watches with different screen resolution than 260x260
        screenResolutionRatio = screenRadius / 130.0; //130.0 = half of vivoactive4 resolution; used for coordinates recalculation

        //pre-compute scaled pixel constants
        rc2 = recalculateCoordinate(2);
        rc4 = recalculateCoordinate(4);
        rc5 = recalculateCoordinate(5);
        rc6 = recalculateCoordinate(6);
        rc7 = recalculateCoordinate(7);
        rc8 = recalculateCoordinate(8);
        rc9 = recalculateCoordinate(9);
        rc10 = recalculateCoordinate(10);
        rc12 = recalculateCoordinate(12);
        rc16 = recalculateCoordinate(16);
        rc17 = recalculateCoordinate(17);
        rc20 = recalculateCoordinate(20);
        rc25 = recalculateCoordinate(25);
        rc30 = recalculateCoordinate(30);
        rc40 = recalculateCoordinate(40);
        rc60 = recalculateCoordinate(60);
        rc76 = recalculateCoordinate(76);
        rc80 = recalculateCoordinate(80);
        rc108 = recalculateCoordinate(108);
        rc136 = recalculateCoordinate(136);

        hourHandLength = rc60;
        minuteHandLength = recalculateCoordinate(90);
        handsTailLength = recalculateCoordinate(15);
        
        if (!((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0))) {
            //array of ticks coordinates
            computeTicks();
        }

        halfHRTextWidth = hrTextDimension[0] / 2;

        heartRateNumberOfSamples = hasHeartRateHistory ? countSamples(SensorHistory.getHeartRateHistory({})) : 0;

        dateAt6Y = screenWidth - Graphics.getFontHeight(font) - rc30;

        //populate HR cache
        var hrIterator = SensorHistory.getHeartRateHistory({});
        minHr = hrIterator.getMin();
        maxHr = hrIterator.getMax();
        hrCache = new [hrCacheSize];
        hrCacheHead = 0;
        if (minHr == null || maxHr == null || heartRateNumberOfSamples == 0) {
            minHr = 0;
            maxHr = 0;
        } else {
            var processed = processHrIterator(hrIterator, heartRateNumberOfSamples);
            for (var i = 0; i < processed.size() && i < hrCacheSize; i++) {
                hrCache[i] = processed[i];
            }
            updateMinMaxHr();
        }
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
                    ticks[i] = computeTickRectangle(angle, rc20, ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, rc20, ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, rc10, ticks1MinWidth);
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
        dc.setPenWidth(rc10);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(screenRadius, screenRadius, screenRadius - rc5, arcDirection, startAngle, endAngle);
    }

    function drawTicks(dc) {
        var coord = new [4];
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 16; i++) {
            var tick = ticks[i];
            if (tick != null) {
                //30-45 ticks
                dc.fillPolygon(tick);

                //mirror pre-computed ticks
            	//15-30 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - tick[j][0], tick[j][1]];
                }
                dc.fillPolygon(coord);

				//45-60 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [tick[j][0], screenWidth - tick[j][1]];
                }
                dc.fillPolygon(coord);

				//0-15 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - tick[j][0], screenWidth - tick[j][1]];
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
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + rc2, handsTailLength + rc2, hourHandWidth + rc4));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + rc2, handsTailLength + rc2, minuteHandWidth + rc4));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        dc.setPenWidth(bulletRadius);
        dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(screenRadius, screenRadius, bulletRadius + rc2);
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
        if ((showLostAndFound != offSettingFlag && 
                (lastPhoneConnectedTime == null || Time.now().subtract(lastPhoneConnectedTime).value() > showLostAndFound)) ||
                (powerSaverDrawn && shouldPowerSave())) {
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
    function drawBackground(dc) {
        //If we have an offscreen buffer that has been written to
        //draw it to the screen.
        if (offscreenBuffer != null) {
            dc.drawBitmap(0, 0, offscreenBuffer);
        }
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

        dc.setClip(screenRadius - halfHRTextWidth, rc30, hrTextDimension[0], hrTextDimension[1]);

        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        //debug rectangle
        //dc.drawRectangle(screenRadius - halfHRTextWidth, rc30, hrTextDimension[0], hrTextDimension[1]);
        dc.drawText(screenRadius, rc25, font, hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawHrGraph(dc, minimalRange) {
        var graphTextHeight = graphFontHeight;

        var leftX = rc40; // 40 pixels from screen border
        var graphHeight = rc80; // fixed height of the graph
        var graphTopY = rc76;
        var graphBottomY = graphTopY + graphHeight + 1;

        var range = maxHr - minHr;
        if (range < minimalRange) {
            range = minimalRange;
        }

        var minValStr = minHr.format("%.0f");
        var maxValStr = maxHr.format("%.0f");

        //draw min and max values
        dc.setColor(graphBordersColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + rc8, graphTopY - graphTextHeight + 3, Graphics.FONT_XTINY, maxValStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(leftX + rc8, graphBottomY - 2, Graphics.FONT_XTINY, minValStr, Graphics.TEXT_JUSTIFY_LEFT);
        //draw rectangle
        dc.setColor(graphBgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(leftX, graphTopY + 1, screenWidth - (2 * leftX) + 1, graphHeight - 1); //for graph
        dc.fillRectangle(leftX + rc2, graphBottomY + rc17, screenWidth - (2 * (leftX + rc2)) + 1, graphTextHeight - 1); //for legend

        var x1;
        var y1 = null;
        var x2 = null;
        var y2 = null;
        var hrVal;
        dc.setPenWidth(graphLineWidth);
        var rangeInv = 1.0 / range;
        for (var i = 0; i < hrCacheSize; i++)  {
            x1 = screenWidth - ((40 + i) * screenResolutionRatio).toNumber();
            hrVal = hrCache[(hrCacheHead + i) % hrCacheSize];
            if (hrVal != null) {
                y1 = graphBottomY - (hrVal - minHr) * rangeInv * graphHeight;
                dc.setColor(getGraphLineColor(hrVal), Graphics.COLOR_TRANSPARENT);
                if (graphStyle == AREA) {
                    dc.drawLine(x1, y1, x1, graphBottomY);
                } else if (x2 != null && y2 != null) {
                    dc.drawLine(x1, y1, x2, y2);
                } else {
                    dc.drawPoint(x1, y1);
                }
            }
            x2 = x1;
            y2 = y1;
        }

        //compute last 5 samples average (10 minutes, 1 sample per 2 min)
        var last5Sum = 0;
        var count = 0;
        var last5HrVal;
        for (var i = 0; i < 5; i++)  {
            last5HrVal = hrCache[(hrCacheHead + i) % hrCacheSize];
            if (last5HrVal != null) {
                last5Sum += last5HrVal;
                count++;
            }
        }
        if (count > 0) {
            var last5Avg = last5Sum / count;
            dc.setColor(graphBgColor, Graphics.COLOR_TRANSPARENT);
            var avgHrStrDim = dc.getTextDimensions(last5Avg.format("%.0f"), Graphics.FONT_XTINY);
            dc.fillRectangle(screenRadius - (avgHrStrDim[0] / 2) - 3, graphTopY - graphTextHeight - 2, avgHrStrDim[0] + 6, graphTextHeight); // for average HR
            dc.setColor(getGraphLineColor(last5Avg), Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenRadius, graphTopY - graphTextHeight - 2, Graphics.FONT_XTINY, last5Avg.format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
        }

        //draw graph borders
        if (graphBordersColor != offSettingFlag) {
            var maxX = leftX + (dc.getTextDimensions(maxValStr, Graphics.FONT_XTINY))[0] + 5;
            var minX = leftX + (dc.getTextDimensions(minValStr, Graphics.FONT_XTINY))[0] + 5;
            dc.setColor(graphBordersColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(leftX, graphTopY, leftX + rc6, graphTopY);
            dc.drawLine(leftX, graphBottomY, leftX + rc6, graphBottomY);
            dc.drawLine(maxX + 5, graphTopY, screenWidth - leftX, graphTopY);
            dc.drawLine(minX + 5, graphBottomY, screenWidth - leftX, graphBottomY);

            var x;
            for (var i = 0; i <= 6; i++) {
                x = leftX + (i * ((screenWidth - (2 * leftX)) / 6 ));
                dc.drawLine(x, graphTopY, x, graphTopY + rc6);
                dc.drawLine(x, graphBottomY - rc5, x, graphBottomY + 1);
            }
        }

        drawHrLegend(dc, leftX, graphBottomY);
    }

    function updateHrCache(clockTime, activityInfo) {
        if (updated == clockTime.min) {
            return;
        }
        
        updated = clockTime.min;
        var currentHr = (activityInfo != null) ? activityInfo.currentHeartRate : null;
        
        if (clockTime.min % 2 == 0) {
            var newHead = (hrCacheHead + hrCacheSize - 1) % hrCacheSize;
            var evicted = hrCache[newHead];
            hrCacheHead = newHead;
            hrCache[hrCacheHead] = (lastOddMinHr != null && currentHr != null) ? 
                (lastOddMinHr + currentHr) / 2.0 :
                (lastOddMinHr != null ? lastOddMinHr : currentHr);

            //incremental min/max update
            if (evicted != null && (evicted == minHr || evicted == maxHr)) {
                //evicted value was an extreme, full rescan needed
                updateMinMaxHr();
            } else if (hrCache[hrCacheHead] != null) {
                if (minHr == 0 || hrCache[hrCacheHead] < minHr) {
                    minHr = hrCache[hrCacheHead];
                }
                if (hrCache[hrCacheHead] > maxHr) {
                    maxHr = hrCache[hrCacheHead];
                }
            }
        } else {
            lastOddMinHr = currentHr;
        }
    }

    function updateMinMaxHr() {
        // Reset min/max
        minHr = 999;
        maxHr = 0;
        
        // Find new min/max in cache
        var val;
        for (var i = 0; i < hrCacheSize; i++) {
            val = hrCache[(hrCacheHead + i) % hrCacheSize];
            if (val != null) {
                if (val < minHr) {
                    minHr = val;
                }
                if (val > maxHr) {
                    maxHr = val;
                }
            }
        }
        
        // Reset if no valid values found
        if (minHr == 999) {
            minHr = 0;
            maxHr = 0;
        }
    }

    function processHrIterator(iterator, numberOfSamples) {
        var batchSize = (numberOfSamples > 180) ? Math.ceil(numberOfSamples / 180) : 1; //dynamically calculate how many values to process in a batch

        var processedValues = [];
        var currentSum = 0;
        var count = 0;
        var countNull = 0;
        var testForSkip = true;

        var item = iterator.next();
        while (item != null) {
            if (testForSkip) { //to prevent "jumping" graph
                testForSkip = false;
                var timestamp = Toybox.Time.Gregorian.info(item.when, Time.FORMAT_SHORT);
                if (timestamp.min % 2 == 0) {
                    item = iterator.next();
                    continue;
                }
            }

            if (item.data != null) {
                currentSum += item.data;
                count++;
            } else {
                countNull++;
            }

            //if we've collected enough values for batch processing
            if ((count + countNull) == batchSize) {
                if (countNull == batchSize) {
                    processedValues.add(null);
                } else {
                    processedValues.add(currentSum / count); //average HR value
                }
                currentSum = 0;
                count = 0;
                countNull = 0;
            }

            item = iterator.next();
        }

        //handle any remaining values that didn't form a complete group
        if (count > 0) {
            processedValues.add(currentSum / count);
        }

        return processedValues;
    }

    function drawHrLegend(dc, x, y) {
        var xPos = x + rc8;
        var yPos = y + rc16;

        dc.setColor(graph60Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos, yPos, Graphics.FONT_XTINY, "60", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(graph70Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos + rc20, yPos, Graphics.FONT_XTINY, "70", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(graph80Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos + rc40, yPos, Graphics.FONT_XTINY, "80", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(graph90Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos + rc60, yPos, Graphics.FONT_XTINY, "90", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(graph100Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos + rc80, yPos, Graphics.FONT_XTINY, "100", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(graph110Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos + rc108, yPos, Graphics.FONT_XTINY, "110", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(graph120Color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xPos + rc136, yPos, Graphics.FONT_XTINY, "110+", Graphics.TEXT_JUSTIFY_LEFT);
    }

    function getGraphLineColor(value) {
        if (value <= 60) {
            return graph60Color; // HR <= 60
        } else if (value <= 70) {
            return graph70Color; // 61-70
        } else if (value <= 80) {
            return graph80Color; // 71-80
        } else if (value <= 90) {
            return graph90Color; // 81-90
        } else if (value <= 100) {
            return graph100Color; // 91-100
        } else if (value <= 110) {
            return graph110Color; // 101-110
        } else {
            return graph120Color; // > 110
        }
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
        var dateInfo = Gregorian.info(Time.today(), Time.FORMAT_MEDIUM);
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
        if (!powerSaver || isAwake) {
            return false;
        }

        var time = System.getClockTime();
        var timeMinOfDay = (time.hour * 60) + time.min;        
        //check if we're in power saver time window
        var inPowerSaverWindow = false;
        if (startPowerSaverMin <= endPowerSaverMin) {
            inPowerSaverWindow = (startPowerSaverMin <= timeMinOfDay && timeMinOfDay < endPowerSaverMin);
        } else {
            inPowerSaverWindow = (startPowerSaverMin <= timeMinOfDay || timeMinOfDay < endPowerSaverMin);
        }
        return inPowerSaverWindow;
    }

    function drawLostAndFound(dc) {
        //clean the screen
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawMessage(dc, "If found, contact:", screenRadius, recalculateCoordinate(45), recalculateCoordinate(230));
        drawMessage(dc, phone, screenRadius, recalculateCoordinate(105), recalculateCoordinate(260));
        drawMessage(dc, email, screenRadius, recalculateCoordinate(138), recalculateCoordinate(260));
        drawMessage(dc, "Thank you!", screenRadius, recalculateCoordinate(195), recalculateCoordinate(220));
    }

    function drawMessage(dc, msg, screenRadius, posY, width) {
        var font = Graphics.FONT_SMALL;
        var textDimension = dc.getTextDimensions(msg, font);

        if (textDimension[0] > width) {
            font = Graphics.FONT_TINY;
            textDimension = dc.getTextDimensions(msg, font);
            if (textDimension[0] > width) {
                font = Graphics.FONT_XTINY;
            }
        }

        dc.drawText(screenRadius, posY, font, msg, Graphics.TEXT_JUSTIFY_CENTER);
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
                sunArcsOffset = rc10;
            } else {
                sunArcsOffset = rc12;
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

        var arcWidth = rc9;
        if (sunArcsOffset == rc10) {
            arcWidth = rc7;
        }

        //draw sunrise
        if (sunriseColor != offSettingFlag) {
	        if (sunriseStartAngle > sunriseEndAngle) {
    	        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
                var step = (sunriseStartAngle - sunriseEndAngle) / arcWidth;
                var baseRadius = (sunArcsOffset == rc10) ? screenRadius - rc20 : screenRadius - rc12;
                var radiusDir = (sunArcsOffset == rc10) ? 1 : -1;
                for (var i = 0; i < arcWidth; i++) {
				    dc.drawArc(screenRadius, screenRadius, baseRadius + (radiusDir * i), Graphics.ARC_CLOCKWISE, sunriseStartAngle - (step * i), sunriseEndAngle);
                }
			} else {
		        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
    			dc.drawArc(screenRadius, screenRadius, screenRadius - rc17, Graphics.ARC_COUNTER_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
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
