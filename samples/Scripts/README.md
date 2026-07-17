# DMX Core 100 — Script Samples

User scripts run on the DMX Core 100 in a sandboxed JavaScript engine and
control the device through the `dmx` API. Create a script under
**Settings → Scripts** in the web UI, paste a sample in, and run it with the
**Run** button — or wire it to an Input Trigger, Schedule, Custom Menu button,
Stream Deck key, or Timeline event using the **Run Script** action.

## How scripts run

- One run per script at a time; a run fired while the previous one is still
  executing is dropped.
- Each run gets a fresh engine — variables do not survive between runs. Use
  `dmx.store` for state that should persist (it also survives restarts).
- Hard limits per run: 30 s wall clock by default (configurable up to 600 s
  per script — sleep time counts), plus statement and memory caps. A script
  that hits a limit is killed and the error shows in the editor's Last Run
  panel.
- Host errors (for example "MQTT client is not connected") can be caught with
  a normal `try/catch`. Cancellation and the wall-clock timeout cannot.

## Contexts

Every run has a `ctx` object:

| Field | Description |
|---|---|
| `ctx.trigger.source` | What started the run: an input-trigger type (`"UDP"`, `"MQTT"`, `"HTTP"`, `"OSC"`, ...), `"MANUAL"` (editor Run button), `"EVENT"` (lifecycle event), `"TIMELINE"`, or `"TRIGGER"` (other surfaces). |
| `ctx.trigger.code` | Code of the Input Trigger that fired, when applicable. |
| `ctx.payload` | Raw payload string from the trigger (or the editor's Test Payload field on manual runs). |
| `ctx.event` | For lifecycle-event runs: `{ name, code }`, e.g. `{ name: "CUESTARTED", code: "CUE3" }`. Otherwise `null`. |
| `ctx.now` | Local device time: `{ hour, minute, minutesSinceMidnight, weekday, iso }`. |

Lifecycle events are enabled per script with the **Run On Events** switches:
`STARTUP`, `CUESTARTED`, `CUEENDED`, `SCHEDULEFIRED`.

## API quick reference

```
Playback     dmx.playCue(code, {fadeIn, fadeOut, loop, dimmer, toggle})
             dmx.playSound(code, {fadeIn, fadeOut, loop, volume, toggle})
             dmx.playTimeline(code)   dmx.stopPlayback()   dmx.fadeOut(ms)
             dmx.fireOutputEvent(code)   dmx.isPlaying(code)
State        dmx.fadeToPreset(code, ms)   dmx.masterDimmer(level, ms)
             dmx.zoneDimmer(zoneCode, level, ms)
Fixtures     dmx.setFixture(code, {intensity, red, green, blue, ...})  // partial update
             dmx.getFixture(code)   dmx.releaseFixture(code)
Effects      dmx.setZoneEffect(zoneCode, effectCode|null)
             dmx.setGlobalEffect(effectCode|null)
Control      dmx.controlValue.get/set/up/down/toggle/status(code)
I/O          dmx.mqtt.publish(topic, payload)
             dmx.osc.send("ip:port", address, value)
Schedules    dmx.schedule.enable/disable/toggle/isEnabled(code)
Sun          dmx.sunrise()   dmx.sunset()      // {hour, minute, minutesSinceMidnight} or null
Store        dmx.store.get/set/delete(key)   dmx.store.keys()
Utility      dmx.sleep(ms)   dmx.log(...)
```

Levels are 0.0–1.0. Codes are the short names shown throughout the UI
(`CUE1`, `P1`, `Z1`, `CVAL1`, ...). `dmx.sunrise()`/`sunset()` need the
device location set under Settings → Preferences.

## Value transform scripts

A Value-mode Input Trigger can name a **Transform Script** that reshapes the
normalized 0..1 value before it drives its target. Transform scripts are
different from regular scripts: they see only the globals `value` and
`payload` (no `dmx`, no `ctx`), their **last expression** is the result
(clamped to 0..1), and they run under a much tighter budget. If the
transform fails, the update is skipped.

## Samples

| File | Shows |
|---|---|
| [motion-light-after-dark.js](motion-light-after-dark.js) | Trigger + sunset check + timed sequence |
| [occupancy-timeout.js](occupancy-timeout.js) | Persistent state with `dmx.store` |
| [toggle-three-looks.js](toggle-three-looks.js) | Cycling presets with a stored counter |
| [mqtt-json-bridge.js](mqtt-json-bridge.js) | Parsing a JSON trigger payload |
| [now-playing-publisher.js](now-playing-publisher.js) | Lifecycle events → MQTT |
| [startup-init.js](startup-init.js) | STARTUP event initialization |
| [evening-show-sequence.js](evening-show-sequence.js) | Multi-step sequence with sleeps |
| [dead-zone-fader.js](dead-zone-fader.js) | Value transform: dead zone + curve |
