# Account Deletion, Data Deletion, Retention

## Account deletion
All user tables reference `auth.users(id) ON DELETE CASCADE`. Deleting the auth user removes profile, trigger preferences, symptom entries and alert preferences (tested).
Clients cannot delete auth users (needs privileged key). Until the team approves a server function for in-app "Delete my account":
- Operators delete via Dashboard → Authentication → Users, or Admin API `deleteUser` from a trusted server.
- A user can delete individual symptom entries/preferences themselves (RLS-scoped).
**Open decision:** approve a server-side "delete account" function (needs JWT validation; service-role key stays server-side).

## Retention
| Data | Retention |
|---|---|
| User health data | Until user deletes it or account |
| environmental_observations | 30 days default via `purge_old_environmental_observations(30)` (service_role only) |
| Auth logs / API logs | Per Supabase plan; contain no symptom notes by design |

Schedule purge (hosted, optional — enable `pg_cron` first):
```sql
select cron.schedule('purge-env-observations', '15 3 * * *',
  $$ select public.purge_old_environmental_observations(30) $$);
```

## Backups
Deleted data may remain in database backups until they rotate (duration depends on your Supabase plan — check it and state it in the privacy notice). Health data is likely "sensitive personal data" under Kenya's Data Protection Act, 2019; confirm consent, privacy notice and deletion promises with the team's compliance owner.
