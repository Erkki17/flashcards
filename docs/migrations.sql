-- Flashcards — Supabase migrations
-- Run in the Supabase SQL Editor. Every statement is idempotent, so running
-- this file twice is safe.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Card columns
--    stage / deck / example were added earlier but never confirmed as applied.
--    Without them, cross-device sync silently drops a card's learning stage.
--    lapses / review_count / last_review are new: cumulative counters that
--    `repetitions` cannot provide, because it resets to 0 on every lapse.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.cards
  ADD COLUMN IF NOT EXISTS stage        INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS deck         TEXT    NOT NULL DEFAULT 'yleinen',
  ADD COLUMN IF NOT EXISTS example      TEXT,
  ADD COLUMN IF NOT EXISTS lapses       INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_review  BIGINT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. review_log — one row per review
--    This is the data FSRS needs to derive stability and difficulty. It cannot
--    be backfilled, which is why it is being added now rather than at migration
--    time. Ratings use FSRS convention so no translation is needed later:
--      1 = Again (Vaikea), 2 = Hard (Uudestaan), 3 = Good (Oikein)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.review_log (
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  card_id      TEXT NOT NULL,
  reviewed_at  TIMESTAMPTZ NOT NULL,
  rating       SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 4),
  state        TEXT NOT NULL DEFAULT 'review',
  direction    TEXT,
  elapsed_days INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The optimizer reads a user's whole history ordered by card and time.
CREATE INDEX IF NOT EXISTS review_log_user_card_time_idx
  ON public.review_log (user_id, card_id, reviewed_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Row-level security — each user sees only their own rows
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.review_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own review_log select" ON public.review_log;
CREATE POLICY "own review_log select" ON public.review_log
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "own review_log insert" ON public.review_log;
CREATE POLICY "own review_log insert" ON public.review_log
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "own review_log delete" ON public.review_log;
CREATE POLICY "own review_log delete" ON public.review_log
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.review_log TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Verify — both should return without error
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'cards' ORDER BY column_name;
-- SELECT count(*) FROM public.review_log;
