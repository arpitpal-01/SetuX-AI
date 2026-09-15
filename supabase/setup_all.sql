-- SETUX AI ONE-TIME SUPABASE SETUP
-- Run this entire file once in Supabase SQL Editor.
-- Before running: create demo Auth users in Authentication > Users if you want demo data.
-- This file never creates passwords or exposes a service-role key.

begin;
create extension if not exists pgcrypto;

do $$ begin create type public.user_role as enum ('USER','OFFICER','ADMIN'); exception when duplicate_object then null; end $$;
do $$ begin create type public.application_status as enum ('DRAFT','SUBMITTED','PROCESSING','VALIDATION_REQUIRED','READY_FOR_ASSIGNMENT','ASSIGNED','UNDER_REVIEW','COMPLETED','REJECTED'); exception when duplicate_object then null; end $$;

create table if not exists public.departments (id uuid primary key default gen_random_uuid(), name text not null unique, description text, created_at timestamptz not null default now());
create table if not exists public.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text not null, email text not null, role public.user_role not null default 'USER', department_id uuid references public.departments(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.services (id uuid primary key default gen_random_uuid(), department_id uuid not null references public.departments(id), name text not null unique, description text, official_link text, required_documents jsonb not null default '[]', required_fields jsonb not null default '[]', created_at timestamptz not null default now());
alter table public.services add column if not exists official_link text;
create table if not exists public.applications (id uuid primary key default gen_random_uuid(), application_number text not null unique, user_id uuid not null references public.profiles(id), service_id uuid references public.services(id), department_id uuid references public.departments(id), assigned_officer_id uuid references public.profiles(id), status public.application_status not null default 'DRAFT', priority text default 'NORMAL', classification_confidence numeric(5,2), submitted_at timestamptz, updated_at timestamptz not null default now());
create table if not exists public.application_documents (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade, document_name text not null, storage_path text not null unique, document_type text not null, file_size integer not null, mime_type text not null, uploaded_at timestamptz not null default now());
create table if not exists public.application_extracted_data (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade, extracted_json jsonb not null default '{}', ocr_text text, confidence numeric(5,2), created_at timestamptz not null default now());
create table if not exists public.application_validation_results (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade, is_valid boolean not null, missing_fields jsonb not null default '[]', missing_documents jsonb not null default '[]', warnings jsonb not null default '[]', created_at timestamptz not null default now());
create table if not exists public.officer_assignments (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade, officer_id uuid not null references public.profiles(id), assigned_by uuid not null references public.profiles(id), assigned_at timestamptz not null default now(), reason text);
create table if not exists public.application_events (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.applications(id) on delete cascade, event_type text not null, description text not null, created_by uuid references public.profiles(id), created_at timestamptz not null default now());
create table if not exists public.audit_logs (id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id), action text not null, entity_type text not null, entity_id uuid, metadata jsonb not null default '{}', created_at timestamptz not null default now());

create unique index if not exists application_extracted_data_application_id_idx on public.application_extracted_data(application_id);
create unique index if not exists application_validation_results_application_id_idx on public.application_validation_results(application_id);
create unique index if not exists officer_assignments_application_officer_idx on public.officer_assignments(application_id, officer_id);
create index if not exists applications_user_id_idx on public.applications(user_id);
create index if not exists applications_officer_id_idx on public.applications(assigned_officer_id);
create index if not exists application_events_app_id_idx on public.application_events(application_id, created_at);

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid(); $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select public.current_role()='ADMIN'; $$;
create or replace function public.is_authorized_officer(app_id uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.applications where id=app_id and assigned_officer_id=auth.uid()); $$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','Citizen'),new.email) on conflict (id) do nothing; return new; end; $$;
do $$ begin create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user(); exception when duplicate_object then null; end $$;
create or replace function public.validate_application_transition() returns trigger language plpgsql security definer set search_path=public as $$ declare allowed boolean:=false; begin if old.status=new.status then return new; end if; allowed:=(old.status,new.status) in (('DRAFT','SUBMITTED'),('SUBMITTED','PROCESSING'),('PROCESSING','VALIDATION_REQUIRED'),('PROCESSING','READY_FOR_ASSIGNMENT'),('VALIDATION_REQUIRED','READY_FOR_ASSIGNMENT'),('READY_FOR_ASSIGNMENT','ASSIGNED'),('ASSIGNED','UNDER_REVIEW'),('UNDER_REVIEW','COMPLETED'),('UNDER_REVIEW','REJECTED')); if not allowed then raise exception 'Invalid application status transition'; end if; new.updated_at:=now(); return new; end; $$;
do $$ begin create trigger application_transition_guard before update of status on public.applications for each row execute function public.validate_application_transition(); exception when duplicate_object then null; end $$;

alter table public.profiles enable row level security;
alter table public.departments enable row level security;
alter table public.services enable row level security;
alter table public.applications enable row level security;
alter table public.application_documents enable row level security;
alter table public.application_extracted_data enable row level security;
alter table public.application_validation_results enable row level security;
alter table public.officer_assignments enable row level security;
alter table public.application_events enable row level security;
alter table public.audit_logs enable row level security;

do $$ begin create policy profiles_self_or_admin on public.profiles for select using (id=auth.uid() or public.is_admin()); exception when duplicate_object then null; end $$;
do $$ begin create policy departments_authenticated_read on public.departments for select to authenticated using (true); exception when duplicate_object then null; end $$;
do $$ begin create policy services_authenticated_read on public.services for select to authenticated using (true); exception when duplicate_object then null; end $$;
do $$ begin create policy applications_scoped_read on public.applications for select using (user_id=auth.uid() or assigned_officer_id=auth.uid() or public.is_admin()); exception when duplicate_object then null; end $$;
do $$ begin create policy users_create_own_applications on public.applications for insert with check (user_id=auth.uid() and status='DRAFT'); exception when duplicate_object then null; end $$;
do $$ begin create policy users_update_drafts on public.applications for update using (user_id=auth.uid() and status='DRAFT') with check (user_id=auth.uid() and status in ('DRAFT','SUBMITTED')); exception when duplicate_object then null; end $$;
do $$ begin create policy officers_update_assigned_cases on public.applications for update using (assigned_officer_id=auth.uid() or public.is_admin()) with check (assigned_officer_id=auth.uid() or public.is_admin()); exception when duplicate_object then null; end $$;
do $$ begin create policy documents_scoped_read on public.application_documents for select using (exists(select 1 from public.applications a where a.id=application_id and (a.user_id=auth.uid() or a.assigned_officer_id=auth.uid() or public.is_admin()))); exception when duplicate_object then null; end $$;
do $$ begin create policy users_upload_own_documents on public.application_documents for insert with check (exists(select 1 from public.applications a where a.id=application_id and a.user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy extracted_scoped_read on public.application_extracted_data for select using (exists(select 1 from public.applications a where a.id=application_id and (a.user_id=auth.uid() or a.assigned_officer_id=auth.uid() or public.is_admin()))); exception when duplicate_object then null; end $$;
do $$ begin create policy users_create_own_extracted on public.application_extracted_data for insert with check (exists(select 1 from public.applications a where a.id=application_id and a.user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy validation_scoped_read on public.application_validation_results for select using (exists(select 1 from public.applications a where a.id=application_id and (a.user_id=auth.uid() or a.assigned_officer_id=auth.uid() or public.is_admin()))); exception when duplicate_object then null; end $$;
do $$ begin create policy users_create_own_validation on public.application_validation_results for insert with check (exists(select 1 from public.applications a where a.id=application_id and a.user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy assignments_scoped_read on public.officer_assignments for select using (officer_id=auth.uid() or assigned_by=auth.uid() or public.is_admin()); exception when duplicate_object then null; end $$;
do $$ begin create policy events_scoped_read on public.application_events for select using (exists(select 1 from public.applications a where a.id=application_id and (a.user_id=auth.uid() or a.assigned_officer_id=auth.uid() or public.is_admin()))); exception when duplicate_object then null; end $$;
do $$ begin create policy users_create_own_events on public.application_events for insert with check (created_by=auth.uid() and exists(select 1 from public.applications a where a.id=application_id and a.user_id=auth.uid())); exception when duplicate_object then null; end $$;
do $$ begin create policy staff_create_case_events on public.application_events for insert with check (created_by=auth.uid() and (public.is_admin() or public.is_authorized_officer(application_id))); exception when duplicate_object then null; end $$;
do $$ begin create policy audit_admin_read on public.audit_logs for select using (public.is_admin()); exception when duplicate_object then null; end $$;

insert into public.departments(name,description) values
('Revenue Department','Certificates and district administration'),('Civil Registration','Birth and death records'),('Social Welfare','Welfare and senior citizen services'),('Health Department','Health and disability certification'),('Police Department','Character verification'),('Food & Civil Supplies','Ration services') on conflict(name) do nothing;

with catalog(name,department,description,docs,fields) as (values
('Birth Certificate','Civil Registration','Birth registration','["Hospital Record","Identity Proof"]'::jsonb,'["Name","Date of Birth","Place of Birth"]'::jsonb),
('Caste Certificate','Revenue Department','Caste certificate','["Identity Proof","Address Proof","Supporting Certificate"]'::jsonb,'["Name","Address","Caste Category"]'::jsonb),
('Income Certificate','Revenue Department','Income proof','["Identity Proof","Address Proof","Income Proof"]'::jsonb,'["Name","Address","Annual Income"]'::jsonb),
('Residential / Domicile Certificate','Revenue Department','Residence proof','["Identity Proof","Address Proof"]'::jsonb,'["Name","Address","Years of Residence"]'::jsonb),
('Death Certificate','Civil Registration','Death registration','["Medical Record","Identity Proof"]'::jsonb,'["Name","Date of Death","Place of Death"]'::jsonb),
('Disability Certificate','Health Department','Disability certification','["Identity Proof","Medical Report"]'::jsonb,'["Name","Disability Type","Disability Percentage"]'::jsonb),
('Character Certificate','Police Department','Character verification','["Identity Proof","Address Proof"]'::jsonb,'["Name","Address","Purpose"]'::jsonb),
('Legal Heir Certificate','Revenue Department','Legal heir verification','["Identity Proof","Death Certificate","Family Proof"]'::jsonb,'["Name","Deceased Name","Relationship"]'::jsonb),
('Ration Card Application','Food & Civil Supplies','Ration card application','["Identity Proof","Address Proof","Family Details"]'::jsonb,'["Head of Family","Address","Family Members"]'::jsonb),
('Senior Citizen Certificate/ID','Social Welfare','Senior citizen certificate','["Identity Proof","Age Proof","Address Proof"]'::jsonb,'["Name","Date of Birth","Address"]'::jsonb))
insert into public.services(department_id,name,description,official_link,required_documents,required_fields)
select d.id,c.name,c.description,'https://services.india.gov.in/?utm_source=chatgpt.com',c.docs,c.fields from catalog c join public.departments d on d.name=c.department
on conflict(name) do update set department_id=excluded.department_id,description=excluded.description,official_link=excluded.official_link,required_documents=excluded.required_documents,required_fields=excluded.required_fields;

-- Exact citizen checklist supplied for the ten services.
update public.services set required_documents='["Hospital/Nursing Home Birth Proof","Parents'' Identity Proof","Address Proof","Parents'' Marriage Certificate (if required)","Application Form + Passport-size Photograph"]', required_fields='["Child''s full name","Date of birth","Place of birth","Parent/guardian name"]' where name='Birth Certificate';
update public.services set required_documents='["Aadhaar Card","Identity Proof (PAN/Voter ID/Passport)","Address Proof (Utility Bill/Ration Card)","Father''s/Relative''s Caste Certificate","School Leaving Certificate (if available)","Self-Declaration Affidavit","Income Certificate (OBC non-creamy-layer, if applicable)","Passport-size Photograph"]', required_fields='["Applicant full name","Address","Caste category","Father/guardian name"]' where name='Caste Certificate';
update public.services set required_documents='["Aadhaar Card","Address Proof","Salary Slip/Form 16 or Self-Declaration Affidavit","Ration Card","Bank Passbook","Passport-size Photograph"]', required_fields='["Applicant full name","Address","Annual income","Income source"]' where name='Income Certificate';
update public.services set required_documents='["Aadhaar Card","Residence Proof for Last 10–15 Years","Birth Certificate or School Leaving Certificate","Identity Proof (Voter ID/Passport)","Affidavit on Stamp Paper","Passport-size Photograph"]', required_fields='["Applicant full name","Current address","Years of residence","Previous address, if any"]' where name='Residential / Domicile Certificate';
update public.services set required_documents='["Hospital Death Summary or Crematorium/Burial Receipt","Deceased''s Identity Proof","Deceased''s Address Proof","Affidavit stating Date, Time & Place of Death","Applicant''s ID Proof and Relationship Proof"]', required_fields='["Deceased person''s full name","Date of death","Place of death","Applicant relationship"]' where name='Death Certificate';
update public.services set required_documents='["Aadhaar Card","Address Proof","Recent Colour Photograph","Medical Reports/Diagnostic Records","Existing Disability Certificate (renewal, if any)"]', required_fields='["Applicant full name","Address","Disability type","Disability percentage"]' where name='Disability Certificate';
update public.services set required_documents='["Aadhaar Card/Identity Proof","Address Proof","Passport-size Photographs","Application Form","Purpose Letter (if applicable)","No-Objection Letter (if required)"]', required_fields='["Applicant full name","Address","Purpose","Institution/employer, if applicable"]' where name='Character Certificate';
update public.services set required_documents='["Deceased''s Death Certificate","Applicant''s Identity Proof","Applicant''s Address Proof","Proof of Relationship","Self-Declaration Affidavit Listing All Heirs","Photographs of Heirs (state-dependent)"]', required_fields='["Applicant full name","Deceased person''s name","Relationship to deceased","Names of all surviving heirs"]' where name='Legal Heir Certificate';
update public.services set required_documents='["Aadhaar Card of All Family Members","Address Proof","Identity Proof of Head of Family","Income Certificate/Proof of Income","Passport-size Photograph of Head of Family","Surrender Certificate (if migrating from another state)"]', required_fields='["Head of family","Full household address","Family members and ages","Monthly/annual income"]' where name='Ration Card Application';
update public.services set required_documents='["Aadhaar Card or Other Photo ID","Proof of Age","Proof of Address","Passport-size Photograph","Income Certificate (pension/welfare, if applicable)"]', required_fields='["Applicant full name","Date of birth","Address","Purpose, if welfare/pension"]' where name='Senior Citizen Certificate/ID';

insert into storage.buckets(id,name,public) values('application-documents','application-documents',false) on conflict(id) do nothing;
do $$ begin create policy private_document_read on storage.objects for select to authenticated using (bucket_id='application-documents' and exists(select 1 from public.applications a where a.id::text=(storage.foldername(name))[2] and (public.is_admin() or a.user_id=auth.uid() or a.assigned_officer_id=auth.uid()))); exception when duplicate_object then null; end $$;
do $$ begin create policy private_document_upload on storage.objects for insert to authenticated with check (bucket_id='application-documents' and (storage.foldername(name))[1]=auth.uid()::text); exception when duplicate_object then null; end $$;

do $$ begin if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='applications') then alter publication supabase_realtime add table public.applications; end if; if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='application_events') then alter publication supabase_realtime add table public.application_events; end if; end $$;

-- Optional demo data. Create these Auth users first, otherwise this block safely skips.
do $$ declare u uuid; o uuid; a uuid; dep uuid; svc uuid; app uuid; begin
select id into u from auth.users where email='demo.citizen@setux.test'; select id into o from auth.users where email='demo.officer@setux.test'; select id into a from auth.users where email='demo.admin@setux.test';
if u is not null and o is not null and a is not null then
  update public.profiles set full_name='Rahul Sharma',role='USER' where id=u; update public.profiles set full_name='Ananya Mehta',role='OFFICER' where id=o; update public.profiles set full_name='Priya Kapoor',role='ADMIN' where id=a;
  select id into dep from public.departments where name='Revenue Department'; update public.profiles set department_id=dep where id=o; select id into svc from public.services where name='Income Certificate';
  insert into public.applications(application_number,user_id,service_id,department_id,assigned_officer_id,status,priority,classification_confidence,submitted_at) values('SETUX-DEMO-0001',u,svc,dep,o,'UNDER_REVIEW','HIGH',96,now()-interval '2 days') on conflict(application_number) do update set assigned_officer_id=excluded.assigned_officer_id,status=excluded.status;
  select id into app from public.applications where application_number='SETUX-DEMO-0001';
  insert into public.application_extracted_data(application_id,extracted_json,confidence) values(app,'{"name":"Rahul Sharma","address":"Ludhiana, Punjab","annual_income":"240000"}',96) on conflict(application_id) do nothing;
  insert into public.application_validation_results(application_id,is_valid,missing_fields,missing_documents,warnings) values(app,true,'[]','[]','["Final decision remains with officer"]') on conflict(application_id) do nothing;
  insert into public.officer_assignments(application_id,officer_id,assigned_by,reason) values(app,o,a,'Correct department and lowest workload') on conflict(application_id,officer_id) do nothing;
  insert into public.application_events(application_id,event_type,description,created_by) values(app,'UNDER_REVIEW','Officer began review',o) on conflict do nothing;
end if; end $$;
commit;

-- Auth demo users must be created in Supabase Authentication with:
-- demo.citizen@setux.test / SetuXDemo2026!
-- demo.officer@setux.test / SetuXDemo2026!
-- demo.admin@setux.test / SetuXDemo2026!
