-- Automatically assign each submitted application to the least-loaded available officer.
create or replace function public.auto_assign_submitted_application()
returns trigger language plpgsql security definer set search_path=public as $$
declare selected_officer uuid;
begin
  if new.status <> 'SUBMITTED' or new.assigned_officer_id is not null or new.department_id is null then
    return new;
  end if;
  select p.id into selected_officer
  from public.profiles p
  where p.role='OFFICER'
    and p.department_id=new.department_id
    and p.is_available=true
    and (select count(*) from public.applications a where a.assigned_officer_id=p.id and a.status not in ('COMPLETED','REJECTED')) < p.max_active_cases
  order by (select count(*) from public.applications a where a.assigned_officer_id=p.id and a.status not in ('COMPLETED','REJECTED')), p.full_name
  limit 1;

  if selected_officer is null then
    insert into public.application_events(application_id,event_type,description,created_by)
    values(new.id,'NO_OFFICER_AVAILABLE','No available officer or capacity in this department',null);
    return new;
  end if;

  update public.applications set assigned_officer_id=selected_officer, status='ASSIGNED' where id=new.id;
  insert into public.officer_assignments(application_id,officer_id,assigned_by,reason)
  values(new.id,selected_officer,null,'Automatic equal workload distribution')
  on conflict(application_id,officer_id) do nothing;
  insert into public.application_events(application_id,event_type,description,created_by)
  values(new.id,'AUTO_ASSIGNED','Automatically assigned to the least-loaded available officer',null);
  return new;
end; $$;

drop trigger if exists auto_assign_submitted_application on public.applications;
create trigger auto_assign_submitted_application
after update of status on public.applications
for each row when (new.status='SUBMITTED' and old.status is distinct from new.status)
execute function public.auto_assign_submitted_application();
