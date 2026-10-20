-- SYNTHETIC DATA ONLY. Runs on `supabase db reset` (local). No users, no health data.
insert into public.environmental_observations
  (provider, location_label, location_precision, coarse_latitude, coarse_longitude,
   observed_at, fetched_at, data_type, data_status, status_reason,
   pm25_ugm3, pm10_ugm3, o3_ugm3, no2_ugm3, temperature_c, humidity_pct)
values
  ('synthetic-provider', 'Nairobi', 'city', -1.3, 36.8,
   now() - interval '10 minutes', now() - interval '5 minutes', 'observed', 'available', null,
   12.4, 25.0, 40.0, 18.5, 24.1, 61),
  ('synthetic-provider', 'Mombasa', 'city', -4.0, 39.7,
   now() - interval '20 minutes', now() - interval '15 minutes', 'estimated', 'partial', 'pm10 sensor offline',
   9.8, null, 35.0, 12.0, 29.4, 78),
  ('synthetic-provider', 'Kisumu', 'city', 0.1, 34.8,
   now() - interval '1 day', now() - interval '1 day', 'observed', 'unavailable', 'provider returned no data',
   null, null, null, null, null, null)
on conflict do nothing;
