// Vision 8 follow-up: later in-app conversations over WS /app/stream/vision8-followup (no phone call).
// The coach works from the person's file ("Akte"), mostly on beliefs and values; the worker updates
// the file from its transcript.

import { VISION8_FOLLOWUP_INSTRUCTIONS, VISION8_FOLLOWUP_OPENING, VISION8_FOLLOWUP_WRAP_UP } from "./prompt.js";

export const VISION8_FOLLOWUP_DESCRIPTOR = {
  id: "vision8-followup",
  tenant: "vision8",
  version: 1,
  persona: { name: "Coach", company: "Vision 8", language: "de-DE" },
  prompt: { instructions: VISION8_FOLLOWUP_INSTRUCTIONS, opening: VISION8_FOLLOWUP_OPENING },
  // Personal data (beliefs, values, life history): EU path only.
  model: { alias: "gemini-live-3.8-eu", allowed: ["gemini-live-3.8-eu"] },
  // Same voice as the intake and the evening call.
  voices: { "gemini-live": "Leda" },
  tools: ["end_call"],
  dataClass: "personal",
  recording: { enabled: false, retentionDays: 30 },
  retentionDays: 30,
  // About ten minutes: wrap-up signal at eight, hard stop at eleven and a half.
  maxCallSeconds: 690,
  wrapUp: { afterSeconds: 480, instruction: VISION8_FOLLOWUP_WRAP_UP },
  outbound: false,
  appSessions: true,
};
