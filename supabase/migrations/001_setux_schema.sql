create extension if not exists "pgcrypto";

create type public.user_role as enum ('USER', 'OFFICER', 'ADMIN');
create type public.application_status as enum ('DRAFT', 'SUBMITTED', 'PROCESSING', 'VALIDATION_REQUIRED', 'READY_FOR_ASSIGNMENT', 'ASSIGNED', 'UNDER_REVIEW', 'COMPLETED', 'REJECTED');

create table public.departments (
  id uuid primary key default gen_random_uuid(), name text not null unique, description text,
  created_at timestamptz not null default now()
);
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade, full_name text not null,
  email text not null, role public.user_role not null default 'USER', department_id uuid references public.departments(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.services (
  id uuid primary key default gen_random_uuid(), department_id uuid not null references public.departments(id),
  name text not null unique, description text, required_documents jsonb not null default '[]', required_fields jsonb not null default '[]',
  created_at timestamptz not null default now()
);
create table public.applications (
  id uuid primary key default gen_random_uuid(), application_number text not null unique,
  user_id uuid not null references public.profiles(id), service_id uuid references public.services(id), department_id uuid references public.departments(id),
  assigned_officer_id uuid references public.profiles(id), status public.application_status not null default 'DRAFT', priority text default 'NORMAL',
  classification_confidence numeric(5,2), submitted_at timestamptz, updated_at timestamptz not null default now()
);
create table public.application_documents (
  id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade,
  document_name text not null, storage_path text not null unique, document_type text not null, file_size integer not null,
  mime_type text not null, uploaded_at timestamptz not null default now()
);
create table public.application_extracted_data (
  id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade,
  extracted_json jsonb not null default '{}', ocr_text text, confidence numeric(5,2), created_at timestamptz not null default now()
);
create table public.application_validation_results (
  id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade,
  is_valid boolean not null, missing_fields jsonb not null default '[]', missing_documents jsonb not null default '[]', warnings jsonb not null default '[]', created_at timestamptz not null default now()
);
create table public.officer_assignments (
  id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade,
  officer_id uuid not null references public.profiles(id), assigned_by uuid not null references public.profiles(id), assigned_at timestamptz not null default now(), reason text
);
create table public.application_events (
  id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade,
  event_type text not null, description text not null, created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id), action text not null,
  entity_type text not null, entity_id uuid, metadata jsonb not null default '{}', created_at timestamptz not null default now()
);

create index applications_user_id_idx on public.applications(user_id);
create index applications_officer_id_idx on public.applications(assigned_officer_id);
create index application_events_app_id_idx on public.application_events(application_id, created_at);
create unique index application_extracted_data_application_id_idx on public.application_extracted_data(application_id);
create unique index application_validation_results_application_id_idx on public.application_validation_results(application_id);
create unique index officer_assignments_application_officer_idx on public.officer_assignments(application_id, officer_id);

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$ select public.current_role() = 'ADMIN'; $$;
create or replace function public.is_authorized_officer(app_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.applications where id = app_id and assigned_officer_id = auth.uid());
$$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', 'Citizen'), new.email);
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.validate_application_transition() returns trigger language plpgsql security definer set search_path = public as $$
declare allowed boolean := false; begin
  if old.status = new.status then return new; end if;
  allowed := (old.status, new.status) in (('DRAFT','SUBMITTED'),('SUBMITTED','PROCESSING'),('PROCESSING','VALIDATION_REQUIRED'),('PROCESSING','READY_FOR_ASSIGNMENT'),('VALIDATION_REQUIRED','READY_FOR_ASSIGNMENT'),('READY_FOR_ASSIGNMENT','ASSIGNED'),('ASSIGNED','UNDER_REVIEW'),('UNDER_REVIEW','COMPLETED'),('UNDER_REVIEW','REJECTED'));
  if not allowed then raise exception 'Invalid application status transition'; end if;
  new.updated_at := now(); return new;
end; $$;
create trigger application_transition_guard before update of status on public.applications for each row execute function public.validate_application_transition();

alter table public.profiles enable row level security; alter table public.departments enable row level security; alter table public.services enable row level security; alter table public.applications enable row level security; alter table public.application_documents enable row level security; alter table public.application_extracted_data enable row level security; alter table public.application_validation_results enable row level security; alter table public.officer_assignments enable row level security; alter table public.application_events enable row level security; alter table public.audit_logs enable row level security;
create policy "profiles self or admin" on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "departments authenticated read" on public.departments for select to authenticated using (true);
create policy "services authenticated read" on public.services for select to authenticated using (true);
create policy "applications scoped read" on public.applications for select using (user_id = auth.uid() or assigned_officer_id = auth.uid() or public.is_admin());
create policy "users create own applications" on public.applications for insert with check (user_id = auth.uid() and status = 'DRAFT');
create policy "users update drafts" on public.applications for update using (user_id = auth.uid() and status = 'DRAFT') with check (user_id = auth.uid() and status in ('DRAFT','SUBMITTED'));
create policy "officers update assigned cases" on public.applications for update using (assigned_officer_id = auth.uid() or public.is_admin()) with check (assigned_officer_id = auth.uid() or public.is_admin());
create policy "documents scoped read" on public.application_documents for select using (exists(select 1 from public.applications a where a.id = application_id and (a.user_id = auth.uid() or a.assigned_officer_id = auth.uid() or public.is_admin())));
create policy "users upload own documents" on public.application_documents for insert with check (exists(select 1 from public.applications a where a.id = application_id and a.user_id = auth.uid()));
create policy "extracted data scoped read" on public.application_extracted_data for select using (exists(select 1 from public.applications a where a.id = application_id and (a.user_id = auth.uid() or a.assigned_officer_id = auth.uid() or public.is_admin())));
create policy "validation scoped read" on public.application_validation_results for select using (exists(select 1 from public.applications a where a.id = application_id and (a.user_id = auth.uid() or a.assigned_officer_id = auth.uid() or public.is_admin())));
create policy "assignments scoped read" on public.officer_assignments for select using (officer_id = auth.uid() or assigned_by = auth.uid() or public.is_admin());
create policy "events scoped read" on public.application_events for select using (exists(select 1 from public.applications a where a.id = application_id and (a.user_id = auth.uid() or a.assigned_officer_id = auth.uid() or public.is_admin())));
create policy "users create own events" on public.application_events for insert with check (created_by = auth.uid() and exists(select 1 from public.applications a where a.id = application_id and a.user_id = auth.uid()));
create policy "staff create case events" on public.application_events for insert with check ((created_by = auth.uid()) and (public.is_admin() or public.is_authorized_officer(application_id)));
create policy "audit admin read" on public.audit_logs for select using (public.is_admin());

insert into public.departments (name, description) values ('Revenue Department','Certificates, income and land services'),('Education Department','Scholarships and student services'),('Social Welfare','Pension and welfare services'),('Civil Registration','Birth and civic records');
insert into public.services (department_id, name, description, required_documents, required_fields) select id, 'Income Certificate', 'Proof of annual income', '["Identity Proof","Address Proof","Income Proof"]', '["Name","Address","Annual Income"]' from public.departments where name = 'Revenue Department';
insert into public.services (department_id, name, description, required_documents, required_fields) select id, 'Scholarship', 'Student scholarship application', '["Identity Proof","Enrollment Proof","Income Proof","Bank Details"]', '["Name","Institution","Course"]' from public.departments where name = 'Education Department';
insert into public.services (department_id, name, description, required_documents, required_fields) select id, 'Pension', 'Social welfare pension enrollment', '["Identity Proof","Age Proof","Bank Details"]', '["Name","Date of Birth","Address"]' from public.departments where name = 'Social Welfare';
insert into public.services (department_id, name, description, required_documents, required_fields) select id, 'Birth Certificate', 'Birth record registration', '["Identity Proof","Hospital Record"]', '["Name","Date of Birth","Place of Birth"]' from public.departments where name = 'Civil Registration';

insert into storage.buckets (id, name, public) values ('application-documents','application-documents',false) on conflict (id) do nothing;
create policy "private document read" on storage.objects for select to authenticated using (
  bucket_id = 'application-documents' and exists (
    select 1 from public.applications a where a.id::text = (storage.foldername(name))[2]
    and (public.is_admin() or a.user_id = auth.uid() or a.assigned_officer_id = auth.uid())
  )
);
create policy "private document upload" on storage.objects for insert to authenticated with check (
  bucket_id = 'application-documents' and (storage.foldername(name))[1] = auth.uid()::text
);