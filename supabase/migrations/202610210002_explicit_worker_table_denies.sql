-- Make the intended default-deny state for worker-owned tables explicit.
-- Authenticated clients must never read or write the event queue or import ID mapping.
begin;
create policy outbox_worker_only on public.outbox_events
  for all to anon, authenticated using (false) with check (false);
create policy external_id_maps_worker_only on public.external_id_maps
  for all to anon, authenticated using (false) with check (false);
commit;
