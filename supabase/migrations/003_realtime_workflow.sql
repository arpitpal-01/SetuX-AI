-- Keep citizen, officer, and admin portals synchronized.
-- Run after 001_setux_schema.sql.

do $$
begin
	if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'applications') then
		alter publication supabase_realtime add table public.applications;
	end if;
	if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'application_events') then
		alter publication supabase_realtime add table public.application_events;
	end if;
end $$;
