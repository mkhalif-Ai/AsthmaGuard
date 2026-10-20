-- =====================================================================
-- AsthmaGuard backend — migration 2 of 2: Row Level Security, grants,
-- contract view, retention function.
-- Principle: default deny. Grants are explicit and column-level where
-- useful; RLS policies tie every user-owned row to auth.uid().
-- =====================================================================

-- Future tables created by the migration role must NOT auto-grant to API roles.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;

-- Enable RLS on every exposed table.
alter table public.profiles                  enable row level security;
alter table public.trigger_preferences       enable row level security;
alter table public.symptom_entries           enable row level security;
alter table public.alert_preferences         enable row level security;
alter table public.environmental_observations enable row level security;

-- Start from zero privileges for client roles.
revoke all on table
  public.profiles, public.trigger_preferences, public.symptom_entries,
  public.alert_preferences, public.environmental_observations
from anon, authenticated;

-- ---------- profiles: read own, update display_name only ----------
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- No INSERT (trigger creates it) and no DELETE (account deletion cascades).

-- ---------- trigger_preferences ----------
-- user_id is insertable/updatable only so client upserts with
-- onConflict: 'user_id,trigger_code' work; RLS WITH CHECK pins it to auth.uid().
grant select, delete on public.trigger_preferences to authenticated;
grant insert (user_id, trigger_code, enabled, threshold_value, threshold_unit)
  on public.trigger_preferences to authenticated;
grant update (user_id, trigger_code, enabled, threshold_value, threshold_unit)
  on public.trigger_preferences to authenticated;

create policy trigger_prefs_select_own on public.trigger_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy trigger_prefs_insert_own on public.trigger_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy trigger_prefs_update_own on public.trigger_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy trigger_prefs_delete_own on public.trigger_preferences
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------- symptom_entries ----------
-- user_id is NOT client-writable at all: it is filled from auth.uid() by default.
grant select, delete on public.symptom_entries to authenticated;
grant insert (occurred_at, symptom_labels, severity, notes)
  on public.symptom_entries to authenticated;
grant update (occurred_at, symptom_labels, severity, notes)
  on public.symptom_entries to authenticated;

create policy symptom_entries_select_own on public.symptom_entries
  for select to authenticated using (user_id = (select auth.uid()));
create policy symptom_entries_insert_own on public.symptom_entries
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy symptom_entries_update_own on public.symptom_entries
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy symptom_entries_delete_own on public.symptom_entries
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------- alert_preferences ----------
grant select, delete on public.alert_preferences to authenticated;
grant insert (user_id, push_enabled, enabled_categories, quiet_hours_start, quiet_hours_end, timezone)
  on public.alert_preferences to authenticated;
grant update (user_id, push_enabled, enabled_categories, quiet_hours_start, quiet_hours_end, timezone)
  on public.alert_preferences to authenticated;

create policy alert_prefs_select_own on public.alert_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy alert_prefs_insert_own on public.alert_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy alert_prefs_update_own on public.alert_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy alert_prefs_delete_own on public.alert_preferences
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------- environmental_observations: read-only for signed-in users ----------
grant select on public.environmental_observations to authenticated;
create policy env_obs_select_authenticated on public.environmental_observations
  for select to authenticated using (true);
-- No write policies/grants: only service_role (server-side) can write.

-- ---------- Contract-shaped read view ----------
-- security_invoker => the caller's RLS/grants apply to the base table.
-- Timestamps are rendered as ISO 8601 UTC with "Z"; every value carries a unit.
-- 'available' data older than 3 hours is reported as 'stale' (PROPOSED threshold).
create view public.environmental_context
with (security_invoker = true) as
select
  o.id,
  o.location_label,
  case
    when o.data_status = 'available' and o.observed_at < now() - interval '3 hours'
      then 'stale'
    else o.data_status::text
  end as status,
  o.status_reason,
  o.provider as source,
  jsonb_build_object('label', o.location_label, 'precision', o.location_precision::text) as location,
  to_char(o.observed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as observed_at,
  to_char(o.fetched_at  at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as fetched_at,
  o.data_type::text as data_type,
  jsonb_build_object(
    'pm25',        jsonb_build_object('value', o.pm25_ugm3,     'unit', 'µg/m³'),
    'pm10',        jsonb_build_object('value', o.pm10_ugm3,     'unit', 'µg/m³'),
    'ozone',       jsonb_build_object('value', o.o3_ugm3,       'unit', 'µg/m³'),
    'no2',         jsonb_build_object('value', o.no2_ugm3,      'unit', 'µg/m³'),
    'so2',         jsonb_build_object('value', o.so2_ugm3,      'unit', 'µg/m³'),
    'temperature', jsonb_build_object('value', o.temperature_c, 'unit', '°C'),
    'humidity',    jsonb_build_object('value', o.humidity_pct,  'unit', '%')
  ) as "values"
from public.environmental_observations o;

revoke all on public.environmental_context from anon, authenticated;
grant select on public.environmental_context to authenticated;

-- ---------- Retention: purge old environmental data (server-side only) ----------
create function public.purge_old_environmental_observations(retention_days integer default 30)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count bigint;
begin
  if retention_days is null or retention_days < 1 then
    raise exception 'retention_days must be >= 1' using errcode = 'invalid_parameter_value';
  end if;
  delete from public.environmental_observations
   where observed_at < now() - make_interval(days => retention_days);
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;
revoke execute on function public.purge_old_environmental_observations(integer)
  from public, anon, authenticated;
grant execute on function public.purge_old_environmental_observations(integer) to service_role;
