// Publish "now playing" to MQTT whenever a cue starts or ends.
//
// Enable Run On Events -> "Cue started" and "Cue ended" on this script.
// Requires the MQTT broker connection to be configured on the device.

if (ctx.event) {
  const topic = "dmxcore/nowplaying";

  if (ctx.event.name === "CUESTARTED") {
    dmx.mqtt.publish(topic, ctx.event.code);
    dmx.log("published start of", ctx.event.code);
  } else if (ctx.event.name === "CUEENDED") {
    dmx.mqtt.publish(topic, "");
    dmx.log("published end of", ctx.event.code);
  }
}
