-- =====================================================================
-- AsthmaGuard backend — migration 1 of 2: types, tables, triggers
-- Status: PROPOSED v1.0. Enum values, severity scale and column names
-- must be marked "Approved" in docs/integration-contract.md before the
-- frontend builds against them.
-- Security (RLS + grants) is applied in migration 2.
-- =====================================================================

-- ---------- Enumerated types (documented enum lists) ----------
create type public.trigger_code as enum (
  'pm25', 'pm10', 'ozone', 'no2', 'so2', 'pollen',
  'cold_air', 'heat', 'high_humidity', 'low_humidity', 'smoke', 'dust'
);

create type public.symptom_label as enum (
  'cough', 'wheeze', 'shortness_of_breath', 'chest_tightness', 'night_symptoms'
);

create type public.env_data_status as enum (
  'available', 'partial', 'stale', 'unavailable', 'error'
);

create type public.env_data_type as enum ('observed', 'estimated', 'forecast');

create type public.location_precision as enum ('country', 'region', 'city', 'district');

create type public.alert_category as enum ('air_quality', 'weather', 'pollen');

-- ---------- Generic helper: maintain updated_at ----------
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- profiles ----------
create table public.profiles (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint profiles_display_name_length
    check (display_name is null or char_length(display_name) between 1 and 80)
);
comment on table public.profiles is
  'One row per authenticated user. Created automatically by trigger on auth.users insert.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create profile on sign-up. SECURITY DEFINER with empty search_path;
-- execute is revoked from all API roles (it only runs as a trigger).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    nullif(btrim(left(new.raw_user_meta_data ->> 'display_name', 80)), '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- trigger_preferences ----------
create table public.trigger_preferences (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                    references auth.users (id) on delete cascade,
  trigger_code    public.trigger_code not null,
  enabled         boolean not null default true,
  threshold_value numeric(8, 2),
  threshold_unit  text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint trigger_preferences_user_trigger_unique unique (user_id, trigger_code),
  constraint trigger_preferences_threshold_nonneg
    check (threshold_value is null or threshold_value >= 0),
  constraint trigger_preferences_threshold_has_unit
    check ((threshold_value is null) = (threshold_unit is null)),
  constraint trigger_preferences_unit_length
    check (threshold_unit is null or char_length(threshold_unit) between 1 and 20)
);
comment on table public.trigger_preferences is
  'Per-user asthma trigger settings. threshold_* only if scientifically justified (team decision).';

create trigger trigger_preferences_set_updated_at
  before update on public.trigger_preferences
  for each row execute function public.set_updated_at();

-- ---------- symptom_entries ----------
create table public.symptom_entries (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  occurred_at    timestamptz not null,
  symptom_labels public.symptom_label[] not null,
  severity       smallint,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint symptom_entries_labels_count
    check (cardinality(symptom_labels) between 1 and 5),
  constraint symptom_entries_severity_range
    check (severity is null or severity between 1 and 5),
  constraint symptom_entries_notes_length
    check (notes is null or char_length(notes) <= 1000)
);
comment on table public.symptom_entries is
  'Private health data. severity scale 1-5 is PROPOSED. notes are sensitive: never log.';

-- Keyset pagination: ORDER BY occurred_at DESC, id DESC
create index symptom_entries_user_occurred_idx
  on public.symptom_entries (user_id, occurred_at desc, id desc);

create trigger symptom_entries_set_updated_at
  before update on public.symptom_entries
  for each row execute function public.set_updated_at();

-- Validation that cannot be a CHECK (depends on now() or subqueries).
create function public.validate_symptom_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.occurred_at is distinct from old.occurred_at then
    if new.occurred_at > now() + interval '5 minutes' then
      raise exception 'occurred_at cannot be in the future'
        using errcode = 'check_violation';
    end if;
  end if;

  if exists (select 1 from unnest(new.symptom_labels) as l where l is null) then
    raise exception 'symptom_labels cannot contain null'
      using errcode = 'check_violation';
  end if;

  if (select count(distinct l) from unnest(new.symptom_labels) as l)
       <> cardinality(new.symptom_labels) then
    raise exception 'symptom_labels cannot contain duplicates'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger symptom_entries_validate
  before insert or update on public.symptom_entries
  for each row execute function public.validate_symptom_entry();

-- ---------- environmental_observations ----------
-- Shared, non-personal reference data. Written ONLY by trusted server code
-- (service_role). Units are fixed by column name; the view in migration 2
-- exposes them in the contract shape.
create table public.environmental_observations (
  id                 uuid primary key default gen_random_uuid(),
  provider           text not null,
  location_label     text not null,
  location_precision public.location_precision not null,
  coarse_latitude    numeric(4, 1),   -- 0.1 degree (~11 km) at most
  coarse_longitude   numeric(4, 1),
  observed_at        timestamptz not null,
  fetched_at         timestamptz not null,
  data_type          public.env_data_type not null,
  data_status        public.env_data_status not null,
  status_reason      text,
  pm25_ugm3          numeric(7, 2),
  pm10_ugm3          numeric(7, 2),
  o3_ugm3            numeric(7, 2),
  no2_ugm3           numeric(7, 2),
  so2_ugm3           numeric(7, 2),
  temperature_c      numeric(4, 1),
  humidity_pct       numeric(4, 1),
  created_at         timestamptz not null default now(),
  constraint env_obs_unique unique (provider, location_label, observed_at),
  constraint env_obs_provider_length check (char_length(provider) between 1 and 100),
  constraint env_obs_label_length check (char_length(location_label) between 1 and 100),
  constraint env_obs_coords_pair check ((coarse_latitude is null) = (coarse_longitude is null)),
  constraint env_obs_lat_range check (coarse_latitude is null or coarse_latitude between -90 and 90),
  constraint env_obs_lon_range check (coarse_longitude is null or coarse_longitude between -180 and 180),
  constraint env_obs_pollutants_nonneg check (
    coalesce(pm25_ugm3, 0) >= 0 and coalesce(pm10_ugm3, 0) >= 0 and
    coalesce(o3_ugm3, 0) >= 0 and coalesce(no2_ugm3, 0) >= 0 and coalesce(so2_ugm3, 0) >= 0
  ),
  constraint env_obs_temperature_range
    check (temperature_c is null or temperature_c between -90 and 60),
  constraint env_obs_humidity_range
    check (humidity_pct is null or humidity_pct between 0 and 100),
  constraint env_obs_reason_required
    check (data_status not in ('unavailable', 'error') or status_reason is not null)
);
comment on table public.environmental_observations is
  'Normalised provider data. NULL = missing (never zero). Retention: purge_old_environmental_observations().';

create index env_obs_location_observed_idx
  on public.environmental_observations (location_label, observed_at desc);

-- ---------- alert_preferences (optional MVP) ----------
create table public.alert_preferences (
  user_id            uuid primary key default auth.uid()
                       references auth.users (id) on delete cascade,
  push_enabled       boolean not null default false,
  enabled_categories public.alert_category[] not null default '{}',
  quiet_hours_start  time,
  quiet_hours_end    time,
  timezone           text not null default 'UTC',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint alert_prefs_quiet_pair
    check ((quiet_hours_start is null) = (quiet_hours_end is null)),
  constraint alert_prefs_categories_count
    check (cardinality(enabled_categories) <= 3),
  constraint alert_prefs_timezone_format
    check (char_length(timezone) <= 64 and timezone ~ '^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$')
);
comment on table public.alert_preferences is
  'Notification settings. Remove if alerts are out of MVP scope.';

create trigger alert_preferences_set_updated_at
  before update on public.alert_preferences
  for each row execute function public.set_updated_at();

-- No audit/security-events table: not necessary for MVP (minimal data policy).
