-- Admin owns routing and final decisions. Officers can only record document verification.

create table if not exists public.application_reviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  officer_id uuid not null references public.profiles(id),
  review_status text not null check (review_status in ('VERIFIED', 'CHANGES_REQUESTED')),
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists application_reviews_application_created_idx on public.application_reviews(application_id, created_at desc);
alter table public.application_reviews enable row level security;

drop policy if exists "officers update assigned cases" on public.applications;
drop policy if exists officers_update_assigned_cases on public.applications;
create policy "admins update applications" on public.applications for update using (public.is_admin()) with check (public.is_admin());
create policy "assigned officers read reviews" on public.application_reviews for select using (public.is_admin() or officer_id = auth.uid());
create policy "assigned officers create reviews" on public.application_reviews for insert with check (officer_id = auth.uid() and public.is_authorized_officer(application_id));

create or replace function public.validate_application_transition() returns trigger language plpgsql security definer set search_path=public as $$
declare allowed boolean := false;
begin
  if old.status = new.status then new.updated_at := now(); return new; end if;
  if new.status in ('COMPLETED', 'REJECTED') and not public.is_admin() then
    raise exception 'Only an admin can make a final decision';
  end if;
  allowed := (old.status, new.status) in (
    ('DRAFT','SUBMITTED'), ('SUBMITTED','PROCESSING'), ('PROCESSING','VALIDATION_REQUIRED'),
    ('PROCESSING','READY_FOR_ASSIGNMENT'), ('VALIDATION_REQUIRED','READY_FOR_ASSIGNMENT'),
    ('SUBMITTED','ASSIGNED'), ('PROCESSING','ASSIGNED'), ('VALIDATION_REQUIRED','ASSIGNED'),
    ('READY_FOR_ASSIGNMENT','ASSIGNED'), ('ASSIGNED','UNDER_REVIEW'), ('UNDER_REVIEW','ASSIGNED'),
    ('ASSIGNED','COMPLETED'), ('UNDER_REVIEW','COMPLETED'), ('ASSIGNED','REJECTED'), ('UNDER_REVIEW','REJECTED')
  );
  if not allowed then raise exception 'Invalid application status transition'; end if;
  new.updated_at := now(); return new;
end; $$;

create or replace function public.assign_application_to_officer(p_application_id uuid, p_officer_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare app_department uuid; officer_department uuid; current_status public.application_status;
begin
  if not public.is_admin() then raise exception 'Only an admin can assign applications'; end if;
  select department_id, status into app_department, current_status from public.applications where id=p_application_id for update;
  if not found then raise exception 'Application not found'; end if;
  select department_id into officer_department from public.profiles where id=p_officer_id and role='OFFICER';
  if not found then raise exception 'Selected user is not an officer'; end if;
  if officer_department is distinct from app_department then raise exception 'Officer must belong to the application department'; end if;
  if current_status in ('COMPLETED','REJECTED') then raise exception 'Closed applications cannot be assigned'; end if;
  update public.applications set assigned_officer_id=p_officer_id, status=case when status in ('SUBMITTED','PROCESSING','VALIDATION_REQUIRED','READY_FOR_ASSIGNMENT') then 'ASSIGNED'::public.application_status else status end where id=p_application_id;
  insert into public.officer_assignments(application_id, officer_id, assigned_by, reason) values(p_application_id, p_officer_id, auth.uid(), coalesce(p_reason, 'Assigned by admin')) on conflict(application_id, officer_id) do update set assigned_by=excluded.assigned_by, assigned_at=now(), reason=excluded.reason;
  insert into public.application_events(application_id,event_type,description,created_by) values(p_application_id,'OFFICER_ASSIGNED','Admin assigned document verification',auth.uid());
end; $$;

create or replace function public.submit_document_review(p_application_id uuid, p_review_status text, p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_role() <> 'OFFICER' then raise exception 'Only officers can submit verification'; end if;
  if not public.is_authorized_officer(p_application_id) then raise exception 'This application is not assigned to you'; end if;
  if p_review_status not in ('VERIFIED','CHANGES_REQUESTED') then raise exception 'Invalid review status'; end if;
  insert into public.application_reviews(application_id,officer_id,review_status,notes) values(p_application_id,auth.uid(),p_review_status,p_notes);
  insert into public.application_events(application_id,event_type,description,created_by) values(p_application_id,'DOCUMENTS_' || p_review_status,'Officer submitted document verification',auth.uid());
end; $$;

create or replace function public.admin_decide_application(p_application_id uuid, p_decision public.application_status, p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Only an admin can make a final decision'; end if;
  if p_decision not in ('COMPLETED','REJECTED') then raise exception 'Decision must be COMPLETED or REJECTED'; end if;
  if not exists(select 1 from public.application_reviews where application_id=p_application_id and review_status='VERIFIED') then raise exception 'An officer must verify documents before final approval'; end if;
  update public.applications set status=p_decision where id=p_application_id and status not in ('COMPLETED','REJECTED');
  if not found then raise exception 'Application is already closed or unavailable'; end if;
  insert into public.application_events(application_id,event_type,description,created_by) values(p_application_id,'ADMIN_' || p_decision,coalesce(p_note,'Final decision by admin'),auth.uid());
end; $$;

revoke all on function public.assign_application_to_officer(uuid,uuid,text) from public;
revoke all on function public.submit_document_review(uuid,text,text) from public;
revoke all on function public.admin_decide_application(uuid,public.application_status,text) from public;
grant execute on function public.assign_application_to_officer(uuid,uuid,text) to authenticated;
grant execute on function public.submit_document_review(uuid,text,text) to authenticated;
grant execute on function public.admin_decide_application(uuid,public.application_status,text) to authenticated;
