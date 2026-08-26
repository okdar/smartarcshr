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

using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.WatchUi;

//on-device settings menu allowing quick on/off toggles for heart rate, power
//saver and lost and found; values are stored in the same properties used by
//the phone app
class SmartArcsHrSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        if (!(item instanceof WatchUi.ToggleMenuItem)) {
            return;
        }
        var id = item.getId();
        var enabled = item.isEnabled();

        if (id.equals("showHr")) {
            toggleColorProperty("hrColor", "savedHrColor", enabled, 0xAAAAAA);
        } else if (id.equals("powerSaver")) {
            Properties.setValue("powerSaver", enabled ? 2 : 1);
        } else if (id.equals("showLostAndFound")) {
            if (enabled) {
                var saved = Storage.getValue("savedShowLostAndFound");
                if (saved == null || saved == -999) {
                    saved = 1;
                }
                Properties.setValue("showLostAndFound", saved);
            } else {
                var current = Properties.getValue("showLostAndFound");
                if (current != -999) {
                    Storage.setValue("savedShowLostAndFound", current);
                }
                Properties.setValue("showLostAndFound", -999);
            }
        }

        //the watch face reloads these values in onShow() when it returns to the foreground
    }

    //toggles a color property that uses -999 as the off value, remembering the
    //last enabled color so it can be restored when switched back on
    function toggleColorProperty(propertyKey, savedKey, enabled, defaultColor) {
        if (enabled) {
            var saved = Storage.getValue(savedKey);
            if (saved == null || saved == -999) {
                saved = defaultColor;
            }
            Properties.setValue(propertyKey, saved);
        } else {
            var current = Properties.getValue(propertyKey);
            if (current != -999) {
                Storage.setValue(savedKey, current);
            }
            Properties.setValue(propertyKey, -999);
        }
    }

}
