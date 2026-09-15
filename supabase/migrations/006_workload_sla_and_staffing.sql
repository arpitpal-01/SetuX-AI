-- Workload balancing, officer capacity, and department completion deadlines.
alter table public.departments add column if not exists sla_hours integer not null default 72 check (sla_hours > 0);
alter table public.profiles add column if not exists is_available boolean not null default true;
alter table public.profiles add column if not exists max_active_cases integer not null default 10 check (max_active_cases > 0);
alter table public.applications add column if not exists due_at timestamptz;
create index if not exists applications_due_at_idx on public.applications(due_at) where status not in ('COMPLETED','REJECTED');

create or replace function public.set_application_due_at() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.due_at is null and new.department_id is not null then
    select coalesce(new.submitted_at, now()) + make_interval(hours => sla_hours) into new.due_at from public.departments where id=new.department_id;
  end if;
  return new;
end; $$;
drop trigger if exists application_due_at on public.applications;
create trigger application_due_at before insert or update of department_id, submitted_at on public.applications for each row execute function public.set_application_due_at();
update public.applications a set due_at=coalesce(a.submitted_at,a.updated_at,now()) + make_interval(hours => d.sla_hours) from public.departments d where a.department_id=d.id and a.due_at is null;

create or replace function public.set_department_sla(p_department_id uuid, p_sla_hours integer) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Only an admin can set the department SLA'; end if;
 if p_sla_hours < 1 or p_sla_hours > 8760 then raise exception 'SLA must be between 1 and 8760 hours'; end if;
 update public.departments set sla_hours=p_sla_hours where id=p_department_id;
 if not found then raise exception 'Department not found'; end if;
end; $$;

create or replace function public.auto_assign_department_backlog(p_department_id uuid) returns integer language plpgsql security definer set search_path=public as $$
declare app record; candidate uuid; assigned_count integer:=0;
begin
 if not public.is_admin() then raise exception 'Only an admin can distribute work'; end if;
 for app in select id from public.applications where department_id=p_department_id and assigned_officer_id is null and status not in ('COMPLETED','REJECTED','DRAFT') order by submitted_at nulls last, updated_at loop
   select p.id into candidate from public.profiles p where p.role='OFFICER' and p.department_id=p_department_id and p.is_available=true and (select count(*) from public.applications a where a.assigned_officer_id=p.id and a.status not in ('COMPLETED','REJECTED')) < p.max_active_cases order by (select count(*) from public.applications a where a.assigned_officer_id=p.id and a.status not in ('COMPLETED','REJECTED')), p.full_name limit 1;
   exit when candidate is null;
   perform public.assign_application_to_officer(app.id,candidate,'Automatic least-workload distribution'); assigned_count:=assigned_count+1;
 end loop;
 return assigned_count;
end; $$;

create or replace function public.add_registered_officer(p_email text, p_department_id uuid, p_full_name text default null) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Only an admin can add officers'; end if;
 if not exists(select 1 from public.departments where id=p_department_id) then raise exception 'Department not found'; end if;
 update public.profiles set role='OFFICER', department_id=p_department_id, is_available=true, full_name=coalesce(nullif(p_full_name,''),full_name), updated_at=now() where lower(email)=lower(trim(p_email));
 if not found then raise exception 'No SetuX account found for this email. Ask the officer to register first.'; end if;
end; $$;

revoke all on function public.set_department_sla(uuid,integer) from public;
revoke all on function public.auto_assign_department_backlog(uuid) from public;
revoke all on function public.add_registered_officer(text,uuid,text) from public;
grant execute on function public.set_department_sla(uuid,integer) to authenticated;
grant execute on function public.auto_assign_department_backlog(uuid) to authenticated;
grant execute on function public.add_registered_officer(text,uuid,text) to authenticated;
