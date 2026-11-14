-- The coach's file ("Akte") on the person: plain German text in fixed sections, rewritten after every contact.
-- last_talk_json: the debrief of the latest follow-up conversation, { summary, insight, at }.
-- All three live on the users row, so DELETE /v1/me removes them.
ALTER TABLE users ADD COLUMN file TEXT;
ALTER TABLE users ADD COLUMN file_updated_at TEXT;
ALTER TABLE users ADD COLUMN last_talk_json TEXT;
