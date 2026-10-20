-- pgTAP tests: user isolation, invalid input, auth failure.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(58);

-- Helper: run SQL as a given API role / user and report 'ok:<rows>' or 'error:<sqlstate>'.
create schema test_helpers;
create function test_helpers.run_as(p_role text, p_uid uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v_rows bigint;
begin
  perform set_config(
    'request.jwt.claims',
    case when p_uid is null then ''
         else json_build_object('sub', p_uid, 'role', p_role)::text end,
    true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
    get diagnostics v_rows = row_count;
    execute 'reset role';
    return 'ok:' || v_rows;
  exception when others then
    execute 'reset role';
    return 'error:' || sqlstate;
  end;
end;
$$;

-- Synthetic users: alice (a...), bob (b...)
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'alice@example.test'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'authenticated', 'authenticated', 'bob@example.test');

insert into public.symptom_entries (id, user_id, occurred_at, symptom_labels) values
  ('a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() - interval '2 hours', array['cough']::public.symptom_label[]),
  ('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() - interval '3 hours', array['wheeze']::public.symptom_label[]);

insert into public.environmental_observations
  (provider, location_label, location_precision, observed_at, fetched_at, data_type, data_status, pm25_ugm3, temperature_c, humidity_pct)
values
  ('pgtap-provider', 'Testville', 'city', now() - interval '5 hours', now() - interval '5 hours', 'observed', 'available', 12.4, 24.1, 61),
  ('pgtap-old', 'Testville', 'city', now() - interval '40 days', now() - interval '40 days', 'observed', 'available', 5, 20, 50);

-- ===== Structural =====
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0::bigint, 'RLS is enabled on every table in schema public');

select is(
  (select count(*) from public.profiles
    where user_id in ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')),
  2::bigint, 'profile row is created automatically on sign-up');

-- ===== Unauthenticated (anon) =====
select is(test_helpers.run_as('anon', null, 'select * from public.profiles'), 'error:42501', 'anon cannot read profiles');
select is(test_helpers.run_as('anon', null, 'select * from public.symptom_entries'), 'error:42501', 'anon cannot read symptom_entries');
select is(test_helpers.run_as('anon', null, 'select * from public.trigger_preferences'), 'error:42501', 'anon cannot read trigger_preferences');
select is(test_helpers.run_as('anon', null, 'select * from public.alert_preferences'), 'error:42501', 'anon cannot read alert_preferences');
select is(test_helpers.run_as('anon', null, 'select * from public.environmental_observations'), 'error:42501', 'anon cannot read environmental_observations');
select is(test_helpers.run_as('anon', null, 'select * from public.environmental_context'), 'error:42501', 'anon cannot read environmental_context view');
select is(test_helpers.run_as('anon', null, $q$insert into public.symptom_entries (occurred_at, symptom_labels) values (now(), array['cough']::public.symptom_label[])$q$), 'error:42501', 'anon cannot insert symptom_entries');

-- ===== profiles =====
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'select * from public.profiles'), 'ok:1', 'alice sees only her own profile');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.profiles set display_name = 'Alice' where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$), 'ok:1', 'alice can update her own display_name');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.profiles set display_name = 'Hacked' where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$q$), 'ok:0', 'alice cannot update bob profile (0 rows)');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.profiles set user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$), 'error:42501', 'alice cannot change profile user_id');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.profiles set display_name = '' where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$), 'error:23514', 'empty display_name rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.profiles (user_id) values ('cccccccc-cccc-cccc-cccc-cccccccccccc')$q$), 'error:42501', 'client cannot insert profiles');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'delete from public.profiles'), 'error:42501', 'client cannot delete profiles');

-- ===== symptom_entries =====
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'select * from public.symptom_entries'), 'ok:1', 'alice sees only her own entries');
select is(test_helpers.run_as('authenticated', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'select * from public.symptom_entries'), 'ok:1', 'bob sees only his own entries');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels, severity, notes) values (now() - interval '1 hour', array['cough','wheeze']::public.symptom_label[], 3, 'synthetic note')$q$), 'ok:1', 'alice can insert a valid entry (user_id filled from auth.uid())');
select is((select count(*) from public.symptom_entries where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 2::bigint, 'inserted entry is owned by alice');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (user_id, occurred_at, symptom_labels) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now(), array['cough']::public.symptom_label[])$q$), 'error:42501', 'alice cannot insert an entry for bob');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.symptom_entries set severity = 5 where id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'$q$), 'ok:0', 'alice cannot update bob entry');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$delete from public.symptom_entries where id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'$q$), 'ok:0', 'alice cannot delete bob entry');
select is((select count(*) from public.symptom_entries where id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'), 1::bigint, 'bob entry is intact');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.symptom_entries set user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' where id = 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1'$q$), 'error:42501', 'alice cannot reassign her entry to bob');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels, severity) values (now(), array['cough']::public.symptom_label[], 9)$q$), 'error:23514', 'severity out of range rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels) values (now(), '{}'::public.symptom_label[])$q$), 'error:23514', 'empty symptom_labels rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels, notes) values (now(), array['cough']::public.symptom_label[], repeat('x', 1001))$q$), 'error:23514', 'notes over 1000 chars rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels) values (now() + interval '1 day', array['cough']::public.symptom_label[])$q$), 'error:23514', 'future occurred_at rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels) values (now(), array['cough','cough']::public.symptom_label[])$q$), 'error:23514', 'duplicate symptom labels rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.symptom_entries (occurred_at, symptom_labels) values (now(), array['not_a_symptom']::text[]::public.symptom_label[])$q$), 'error:22P02', 'unknown symptom label rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$delete from public.symptom_entries where id = 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1'$q$), 'ok:1', 'alice can delete her own entry');

-- ===== trigger_preferences =====
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.trigger_preferences (user_id, trigger_code, enabled) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'pm25', true)$q$), 'ok:1', 'alice can save her own trigger preference');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.trigger_preferences (user_id, trigger_code) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'pollen')$q$), 'error:42501', 'alice cannot write a preference for bob (RLS)');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.trigger_preferences (user_id, trigger_code) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'pm25')$q$), 'error:23505', 'duplicate trigger_code per user rejected');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.trigger_preferences (user_id, trigger_code, threshold_value) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'pm10', 35)$q$), 'error:23514', 'threshold without unit rejected');
select is(test_helpers.run_as('authenticated', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', $q$select * from public.trigger_preferences where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$), 'ok:0', 'bob cannot read alice preferences');
select is(test_helpers.run_as('authenticated', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', $q$update public.trigger_preferences set enabled = false where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$), 'ok:0', 'bob cannot update alice preferences');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.trigger_preferences set enabled = false where trigger_code = 'pm25'$q$), 'ok:1', 'alice can update her own preference');

-- ===== alert_preferences =====
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.alert_preferences (user_id, push_enabled, enabled_categories) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true, array['air_quality']::public.alert_category[])$q$), 'ok:1', 'alice can save her alert preferences');
select is(test_helpers.run_as('authenticated', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', $q$select * from public.alert_preferences where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$), 'ok:0', 'bob cannot read alice alert preferences');
select is(test_helpers.run_as('authenticated', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', $q$insert into public.alert_preferences (user_id, quiet_hours_start) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22:00')$q$), 'error:23514', 'half-set quiet hours rejected');

-- ===== environmental data =====
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$select * from public.environmental_observations where provider = 'pgtap-provider'$q$), 'ok:1', 'signed-in user can read environmental observations');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$insert into public.environmental_observations (provider, location_label, location_precision, observed_at, fetched_at, data_type, data_status) values ('x', 'x', 'city', now(), now(), 'observed', 'available')$q$), 'error:42501', 'client cannot insert environmental data');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$update public.environmental_observations set pm25_ugm3 = 0$q$), 'error:42501', 'client cannot update environmental data');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'delete from public.environmental_observations'), 'error:42501', 'client cannot delete environmental data');
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', $q$select * from public.environmental_context where source = 'pgtap-provider'$q$), 'ok:1', 'signed-in user can read environmental_context view');
select is((select "values" -> 'pm25' ->> 'unit' from public.environmental_context where source = 'pgtap-provider'), 'µg/m³', 'view includes units');
select is((select "values" -> 'pm10' ->> 'value' from public.environmental_context where source = 'pgtap-provider'), null, 'missing pm10 is null, not zero');
select is((select status from public.environmental_context where source = 'pgtap-provider'), 'stale', 'available data older than 3h is reported as stale');
select matches((select observed_at from public.environmental_context where source = 'pgtap-provider'), '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', 'observed_at is ISO 8601 UTC with Z');

-- ===== retention function =====
select is(test_helpers.run_as('authenticated', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'select public.purge_old_environmental_observations(30)'), 'error:42501', 'clients cannot call purge function');
select is(test_helpers.run_as('anon', null, 'select public.purge_old_environmental_observations(30)'), 'error:42501', 'anon cannot call purge function');
select is(test_helpers.run_as('service_role', null, 'select public.purge_old_environmental_observations(30)'), 'ok:1', 'service_role can call purge function');
select is((select count(*) from public.environmental_observations where provider = 'pgtap-old'), 0::bigint, 'old observation was purged');
select is((select count(*) from public.environmental_observations where provider = 'pgtap-provider'), 1::bigint, 'recent observation was kept');

-- ===== account deletion cascades =====
delete from auth.users where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select is(
  (select (select count(*) from public.profiles           where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
        + (select count(*) from public.symptom_entries    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
        + (select count(*) from public.trigger_preferences where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
        + (select count(*) from public.alert_preferences   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  0::bigint, 'deleting a user removes all of their rows');
select is((select count(*) from public.symptom_entries where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), 1::bigint, 'other users data is unaffected by deletion');

select * from finish();
rollback;
