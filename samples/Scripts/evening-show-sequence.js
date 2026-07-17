// A small timed sequence: pre-show look, show cue, then back to ambient.
//
// Fire it from a schedule, a Custom Menu button, or a Stream Deck key.
// Raise the script timeout to cover the whole sequence (sleep time counts
// toward the wall-clock limit).

dmx.log("pre-show look");
dmx.fadeToPreset("P2", 3000);
dmx.sleep(30 * 1000);

dmx.log("show");
dmx.playCue("CUE2", { fadeIn: 1000, loop: 1 });

// Wait for the cue to finish (poll rather than guessing the duration)
while (dmx.isPlaying("CUE2")) {
  dmx.sleep(1000);
}

dmx.log("back to ambient");
dmx.fadeToPreset("P1", 5000);
