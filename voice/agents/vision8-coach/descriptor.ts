// Vision 8 coach: outbound evening accountability call for the Vision 8 app (POST /outbound/vision8-coach).

import { VISION8_COACH_INSTRUCTIONS, VISION8_COACH_OPENING } from "./prompt.js";

export const VISION8_COACH_DESCRIPTOR = {
  id: "vision8-coach",
  tenant: "vision8",
  version: 1,
  persona: { name: "Clara", company: "Vision 8", language: "de-DE" },
  prompt: { instructions: VISION8_COACH_INSTRUCTIONS, opening: VISION8_COACH_OPENING },
  // Personal data (goals, how the day went): EU path only.
  model: { alias: "gemini-live-3.8-eu", allowed: ["gemini-live-3.8-eu"] },
  // Gemini "Leda": a natural German voice.
  voices: { "gemini-live": "Leda" },
  tools: ["save_checkin", "end_call"],
  dataClass: "personal",
  recording: { enabled: false, retentionDays: 30 },
  retentionDays: 30,
  maxCallSeconds: 480,
  outbound: true,
};
