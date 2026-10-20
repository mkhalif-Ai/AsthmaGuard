# Authentication Configuration Guide (no secrets)

Method (PROPOSED): Supabase Auth email + password. Profile row created automatically by DB trigger.

## Dashboard → Authentication settings
- Email provider: enabled. **Confirm email: ON.** Disable all unused providers and **anonymous sign-ins**.
- Password: minimum length 12 recommended (Supabase minimum 8); enable leaked-password protection if your plan offers it.
- Sessions: JWT expiry 3600 s; **refresh token rotation ON**.
- URL configuration: Site URL and a redirect allow-list containing only your app deep link (e.g. `your-app-scheme://login-callback/`).
- Rate limits: keep defaults or stricter; do not disable.
- Email templates: remove anything revealing whether an account exists.

## Dashboard → API / Data API
- Exposed schemas: `public` only. Max rows: **100** (local: `[api] max_rows = 100` in `supabase/config.toml`).
- Leave Realtime off for these tables unless a feature needs it.

## Local `supabase/config.toml` (after `supabase init`)
```toml
[api]
max_rows = 100
[auth]
enable_signup = true
enable_anonymous_sign_ins = false
minimum_password_length = 12
enable_refresh_token_rotation = true
[auth.email]
enable_confirmations = true
```

## Keys
| Key | Where it may live |
|---|---|
| URL + anon/publishable key | Flutter config via `--dart-define` or git-ignored `.env` |
| **service_role key** | Server/secret manager only. Never Flutter, never Git, never logs |
| Provider API key | Server-side secret only |

Enable GitHub **secret scanning + push protection** (Repo → Settings → Code security). If a key is ever committed: rotate it immediately — deleting the commit is not enough.

## Do not log
Passwords, access/refresh tokens, symptom notes, precise location.
