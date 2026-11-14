// Vision 8 contract revision: a short conversation about the drafted goal contract, held in the app over
// WS /app/stream/vision8-revise (no phone call). The app rewrites the contract from its transcript.

import { VISION8_REVISE_INSTRUCTIONS, VISION8_REVISE_OPENING, VISION8_REVISE_WRAP_UP } from "./prompt.js";

export const VISION8_REVISE_DESCRIPTOR = {
  id: "vision8-revise",
  tenant: "vision8",
  version: 1,
  persona: { name: "Clara", company: "Vision 8", language: "de-DE" },
  prompt: { instructions: VISION8_REVISE_INSTRUCTIONS, opening: VISION8_REVISE_OPENING },
  // Personal data (life situation, values, goals): EU path only.
  model: { alias: "gemini-live-3.8-eu", allowed: ["gemini-live-3.8-eu"] },
  // Same voice as the vision8-coach evening call.
  voices: { "gemini-live": "Leda" },
  tools: ["end_call"],
  dataClass: "personal",
  recording: { enabled: false, retentionDays: 30 },
  retentionDays: 30,
  // About five minutes: wrap-up signal at four, hard stop at six and a half.
  maxCallSeconds: 390,
  wrapUp: { afterSeconds: 240, instruction: VISION8_REVISE_WRAP_UP },
  outbound: false,
  appSessions: true,
};
