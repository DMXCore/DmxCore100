// Bring the venue to a known state after power-up.
//
// Enable Run On Events -> "Device startup" on this script. It runs once at
// the end of every boot: applies the ambient look appropriate for the time
// of day and announces the restart over MQTT.

const sunset = dmx.sunset();
const evening = sunset !== null &&
  ctx.now.minutesSinceMidnight >= sunset.minutesSinceMidnight;

dmx.fadeToPreset(evening ? "P3" : "P1", 3000);

try {
  dmx.mqtt.publish("dmxcore/status", "restarted " + ctx.now.iso);
} catch (e) {
  // Broker may not be up yet right after a site-wide power cycle
  dmx.log("MQTT not available:", e.message);
}

dmx.log("startup init done (evening:", evening + ")");
