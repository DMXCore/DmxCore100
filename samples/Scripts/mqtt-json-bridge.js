// Bridge a JSON MQTT message onto fixtures and audio.
//
// Wire this to an MQTT Input Trigger (edge mode, Run Script action). A
// building-management system publishes something like:
//
//   { "mode": "meeting", "level": 0.7 }
//
// The raw message arrives as ctx.payload. Try it from the editor by putting
// the JSON in the Test Payload field and pressing Run.

if (!ctx.payload) {
  dmx.log("no payload - nothing to do");
} else {
  let msg;
  try {
    msg = JSON.parse(ctx.payload);
  } catch (e) {
    dmx.log("bad JSON payload:", ctx.payload);
  }

  if (msg) {
    switch (msg.mode) {
      case "meeting":
        dmx.fadeToPreset("P2", 1500);
        dmx.controlValue.set("CVAL1", 0.25); // duck background audio
        break;

      case "presentation":
        dmx.fadeToPreset("P3", 1500);
        dmx.controlValue.set("CVAL1", 0);
        break;

      default:
        dmx.fadeToPreset("P1", 1500);
        dmx.controlValue.set("CVAL1", 0.6);
        break;
    }

    if (typeof msg.level === "number") {
      dmx.masterDimmer(msg.level, 1000);
    }

    dmx.log("applied mode", msg.mode, "level", msg.level);
  }
}
