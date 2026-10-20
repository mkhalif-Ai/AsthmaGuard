# Integration Contract — Backend Implementation Notes

Architecture proposal: **Supabase client + RLS** for all user-owned CRUD. No REST/Edge endpoints exist. Environmental *reads* use the `environmental_context` view; environmental *writes* (provider ingestion) are deferred until a server function is approved.

## Decisions needing "Approved" (backend + frontend)
| # | Decision | Backend proposal | Status |
|---|---|---|---|
| 1 | Supabase-direct vs custom API | Supabase-direct + RLS | PROPOSED |
| 2 | Auth method | Email/password, email confirmation ON | PROPOSED |
| 3 | Enum lists (triggers, symptoms, status) | See data-dictionary.md | PROPOSED |
| 4 | Severity scale | Integer 1–5, nullable | PROPOSED |
| 5 | Timestamps | DB returns `+00:00` for table columns; view returns `Z`. Frontend should call `DateTime.parse(...).toUtc()` | PROPOSED |
| 6 | Errors | Use Supabase SDK errors (table below), not the custom envelope | PROPOSED |
| 7 | Pagination | Keyset on `(occurred_at desc, id desc)`, max 100 rows | PROPOSED |
| 8 | Stale threshold | `available` older than 3 h → `stale` | PROPOSED |
| 9 | Env data ingestion + delete-account functions | Not built until approved | OPEN |

## Operation → Supabase call (Flutter, `supabase_flutter`)
```dart
// Read own profile
final p = await supabase.from('profiles').select().maybeSingle();            // null => empty state
// Update own profile
await supabase.from('profiles').update({'display_name': name}).eq('user_id', uid);
// Save trigger preference (upsert; RLS pins user_id)
await supabase.from('trigger_preferences').upsert(
  {'user_id': uid, 'trigger_code': 'pm25', 'enabled': true},
  onConflict: 'user_id,trigger_code');
// Create symptom entry (do NOT send user_id)
final e = await supabase.from('symptom_entries').insert({
  'occurred_at': DateTime.now().toUtc().toIso8601String(),
  'symptom_labels': ['cough'], 'severity': 2, 'notes': null,
}).select().single();
// History page 1, then next page using last row as cursor
final page = await supabase.from('symptom_entries').select()
  .order('occurred_at', ascending: false).order('id', ascending: false).limit(20);
final next = await supabase.from('symptom_entries').select()
  .or('occurred_at.lt.$ts,and(occurred_at.eq.$ts,id.lt.$id)')
  .order('occurred_at', ascending: false).order('id', ascending: false).limit(20);
// Environmental context
final env = await supabase.from('environmental_context').select()
  .eq('location_label', 'Nairobi').order('observed_at', ascending: false).limit(1).maybeSingle();
```

## Error mapping
| Situation | Signal | App behaviour |
|---|---|---|
| Not signed in / expired JWT | HTTP 401, `PGRST301` | Refresh session or prompt sign-in |
| RLS/permission denied | HTTP 403, code `42501` | Safe message, no retry loop |
| Check/enum/format violation | HTTP 400, `23514` / `22P02` | Field-level feedback |
| Duplicate (e.g. trigger_code) | HTTP 409, `23505` | Treat as update/already saved |
| Other user's row / missing row | 0 rows / `null` | Empty / not-found state |
| Rate limit | HTTP 429 | Retry-later state |
| 5xx / timeout | exception | Retry button; keep local input |

Sample payloads: `docs/backend/fixtures/`.
