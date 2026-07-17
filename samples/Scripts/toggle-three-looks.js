// One button, three looks.
//
// Wire this to any button-style surface (Stream Deck key, keypad, Custom
// Menu button, digital input) with the "Run Script" action. Each press
// cycles: look 1 -> look 2 -> look 3 -> off -> look 1 ...

const LOOKS = ["P1", "P2", "P3", null];

const step = dmx.store.get("step") || 0;
const look = LOOKS[step % LOOKS.length];

if (look === null) {
  dmx.log("cycle: off");
  dmx.fadeOut(2000);
} else {
  dmx.log("cycle: applying", look);
  dmx.fadeToPreset(look, 1000);
}

dmx.store.set("step", (step + 1) % LOOKS.length);
