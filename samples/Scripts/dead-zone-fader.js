// Value TRANSFORM script: dead zone + gentle curve for a wall fader.
//
// This is not a regular script - select it as the "Transform Script" on a
// Value-mode Input Trigger. It sees the globals `value` (normalized 0..1)
// and `payload` (the raw message), and its LAST EXPRESSION is the result,
// clamped to 0..1. No dmx or ctx here, and the budget is tight: keep
// transforms to pure math.
//
// Below 5% the output snaps to 0 (so a slightly-off fader really means
// off); above that, a squared curve gives finer control at low levels.

value < 0.05 ? 0 : value * value;
