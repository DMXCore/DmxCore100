// Motion light, but only after dark.
//
// Wire this to an Input Trigger (UDP, HTTP, MQTT, ...) fired by a motion
// sensor, using the "Run Script" action. During the day it does nothing;
// after sunset it brings up the walkway look for 5 minutes, then fades
// back out.
//
// Requires: preset P1 (walkway look), device location set (for sunset),
// script timeout raised to ~360 seconds (the sleep counts against it).

const sunset = dmx.sunset();
const sunrise = dmx.sunrise();

// No location configured -> behave like a plain motion light
const dark = sunset === null ||
  ctx.now.minutesSinceMidnight >= sunset.minutesSinceMidnight ||
  ctx.now.minutesSinceMidnight < sunrise.minutesSinceMidnight;

if (!dark) {
  dmx.log("daylight - ignoring motion from", ctx.trigger.source);
} else {
  dmx.log("motion after dark - walkway on");
  dmx.fadeToPreset("P1", 1000);

  dmx.sleep(5 * 60 * 1000);

  dmx.log("timeout - walkway off");
  dmx.fadeOut(5000);
}
