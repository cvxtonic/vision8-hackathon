// Vision 8 intake: first conversation in the Vision 8 app, held in the app over WS /app/stream/vision8-intake
// (no phone call). The app writes vision and SMART goals from its transcript.

import { VISION8_INTAKE_INSTRUCTIONS, VISION8_INTAKE_OPENING, VISION8_INTAKE_WRAP_UP } from "./prompt.js";

export const VISION8_INTAKE_DESCRIPTOR = {
  id: "vision8-intake",
  tenant: "vision8",
  version: 1,
  persona: { name: "Coach", company: "Vision 8", language: "de-DE" },
  prompt: { instructions: VISION8_INTAKE_INSTRUCTIONS, opening: VISION8_INTAKE_OPENING },
  // Personal data (life situation, values, goals): EU path only.
  model: { alias: "gemini-live-3.8-eu", allowed: ["gemini-live-3.8-eu"] },
  // Same voice as the vision8-coach evening call.
  voices: { "gemini-live": "Leda" },
  tools: ["end_call"],
  dataClass: "personal",
  recording: { enabled: false, retentionDays: 30 },
  retentionDays: 30,
  // About ten minutes: wrap-up signal at eight, hard stop at eleven and a half.
  maxCallSeconds: 690,
  wrapUp: { afterSeconds: 480, instruction: VISION8_INTAKE_WRAP_UP },
  outbound: false,
  appSessions: true,
};
