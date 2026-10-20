# AsthmaGuard Backend — Setup Guide

Stack (PROPOSED, pending team confirmation): Supabase Auth + PostgreSQL with Row Level Security.
The frontend reads/writes user-owned tables **directly through the Supabase SDK**; RLS is the authorization layer.
No custom endpoints or Edge Functions are built until the frontend agrees to them (see `integration-notes.md`).

## Prerequisites
- Git, Docker Desktop (running), [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)

## Run locally from a clean checkout
```bash
supabase start          # starts local Postgres/Auth/Studio in Docker
supabase db reset       # applies supabase/migrations/* then supabase/seed.sql (synthetic only)
supabase test db        # runs pgTAP tests (user isolation, invalid input, auth failure)
supabase stop
```
`supabase start` prints the local API URL and anon key — put them in your own git-ignored `.env`.

## Apply to a hosted project (after review/merge)
```bash
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase db push        # applies pending migrations
```
Then follow `auth-configuration.md` for dashboard settings. Never paste keys into the repo.

## Layout
| Path | Purpose |
|---|---|
| `supabase/migrations/` | Versioned schema, RLS, grants |
| `supabase/seed.sql` | Synthetic environmental rows only |
| `supabase/tests/database/` | pgTAP tests |
| `docs/backend/data-dictionary.md` | ERD + field reference |
| `docs/backend/rls-policy-matrix.md` | Who can do what |
| `docs/backend/auth-configuration.md` | Auth setup guide (no secrets) |
| `docs/backend/integration-notes.md` | Contract mapping, SDK examples, open decisions |
| `docs/backend/data-lifecycle.md` | Deletion, retention, backups |
| `docs/backend/fixtures/` | Sample JSON matching the contract |

## Changing the schema
Never edit an applied migration. Add a new file: `supabase migration new <name>`, add tests, open a PR to `develop`.
