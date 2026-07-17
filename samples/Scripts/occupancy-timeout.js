// Occupancy with a rolling timeout, using dmx.store for state.
//
// Fire this from a motion/occupancy sensor trigger. The first motion turns
// the room on; each further motion just pushes the deadline out. A second
// copy of the mechanism could run from a schedule to sweep at closing time.
//
// Because each run is independent (and overlapping runs are dropped), the
// timeout lives in the store rather than in a long sleep: this script also
// subscribes to Run On Events -> Schedule fired, where a every-minute
// schedule acts as the tick that checks the deadline.

// Kept simple on purpose: deadlines don't survive midnight rollover, so a
// room occupied at 23:55 turns off at 00:00. Good enough for most venues;
// store an absolute date if yours runs around the clock.
const HOLD_MINUTES = 10;

if (ctx.event && ctx.event.name === "SCHEDULEFIRED") {
  // Tick: turn off when the deadline has passed
  const deadline = dmx.store.get("occupiedUntil") || 0;
  const nowMinutes = ctx.now.minutesSinceMidnight;

  if (deadline > 0 && nowMinutes >= deadline) {
    dmx.log("occupancy timeout - room off");
    dmx.store.set("occupiedUntil", 0);
    dmx.fadeOut(4000);
  }
} else {
  // Motion: switch on (only when currently off) and push the deadline
  const wasOff = (dmx.store.get("occupiedUntil") || 0) === 0;
  dmx.store.set("occupiedUntil", ctx.now.minutesSinceMidnight + HOLD_MINUTES);

  if (wasOff) {
    dmx.log("occupied - room on");
    dmx.fadeToPreset("P1", 800);
  }
}
