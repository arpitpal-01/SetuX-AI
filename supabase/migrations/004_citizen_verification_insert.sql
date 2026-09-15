-- Allow a citizen to save the fields and verification result for their own draft.
-- Business decisions remain with officers; this only records submission checks.

create policy "users create own extracted data" on public.application_extracted_data
for insert with check (exists (
  select 1 from public.applications a where a.id = application_id and a.user_id = auth.uid()
));

create policy "users create own validation results" on public.application_validation_results
for insert with check (exists (
  select 1 from public.applications a where a.id = application_id and a.user_id = auth.uid()
));