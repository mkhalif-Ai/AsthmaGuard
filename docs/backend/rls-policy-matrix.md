# RLS Policy & Grant Matrix

Default deny. `anon` has **no** access to any table. "own" = `user_id = auth.uid()`.

| Table | anon | authenticated SELECT | INSERT | UPDATE | DELETE | service_role |
|---|---|---|---|---|---|---|
| profiles | none | own | none (trigger creates) | own, column `display_name` only | none (cascade on account deletion) | full |
| trigger_preferences | none | own | own | own | own | full |
| symptom_entries | none | own | own (`user_id` auto-filled, not writable) | own (content columns only) | own | full |
| alert_preferences | none | own | own | own | own | full |
| environmental_observations | none | all rows (non-personal) | none | none | none | full (server writes) |
| environmental_context (view) | none | via invoker RLS | – | – | – | – |
| purge_old_environmental_observations() | none | none | – | – | – | execute |

Behaviour to expect in the app:
- Reading/updating/deleting **another user's** row returns **0 rows**, not an error → treat as not found.
- Inserting with another user's `user_id` → `42501` (HTTP 403).
- Constraint violations → `23514` / `23505` / `22P02` (HTTP 400/409).

Every row above is enforced by `supabase/tests/database/01_rls_isolation.test.sql`.
