-- SetuX AI demo seed
-- First create these three accounts through /auth using the credentials below.
-- Then run this file in Supabase SQL Editor. It only inserts missing demo rows.

begin;

do $$
declare
  demo_user uuid;
  demo_officer uuid;
  demo_admin uuid;
  revenue uuid;
  education uuid;
  welfare uuid;
  registration uuid;
  income_service uuid;
  scholarship_service uuid;
  pension_service uuid;
  birth_service uuid;
  income_app uuid;
  scholarship_app uuid;
  pension_app uuid;
begin
  select id into demo_user from auth.users where email = 'demo.citizen@setux.test';
  select id into demo_officer from auth.users where email = 'demo.officer@setux.test';
  select id into demo_admin from auth.users where email = 'demo.admin@setux.test';

  if demo_user is null or demo_officer is null or demo_admin is null then
    raise exception 'Create the three demo accounts through /auth before running this seed.';
  end if;

  update public.profiles set full_name = 'Rahul Sharma', role = 'USER' where id = demo_user;
  update public.profiles set full_name = 'Ananya Mehta', role = 'OFFICER' where id = demo_officer;
  update public.profiles set full_name = 'Priya Kapoor', role = 'ADMIN' where id = demo_admin;

  select id into revenue from public.departments where name = 'Revenue Department';
  select id into education from public.departments where name = 'Education Department';
  select id into welfare from public.departments where name = 'Social Welfare';
  select id into registration from public.departments where name = 'Civil Registration';
  update public.profiles set department_id = revenue where id = demo_officer;

  select id into income_service from public.services where name = 'Income Certificate';
  select id into scholarship_service from public.services where name = 'Scholarship';
  select id into pension_service from public.services where name = 'Pension';
  select id into birth_service from public.services where name = 'Birth Certificate';

  insert into public.applications (application_number, user_id, service_id, department_id, assigned_officer_id, status, priority, classification_confidence, submitted_at)
  values ('SETUX-DEMO-0001', demo_user, income_service, revenue, demo_officer, 'UNDER_REVIEW', 'HIGH', 96.00, now() - interval '2 days')
  on conflict (application_number) do update set assigned_officer_id = excluded.assigned_officer_id, status = excluded.status, priority = excluded.priority;
  select id into income_app from public.applications where application_number = 'SETUX-DEMO-0001';

  insert into public.applications (application_number, user_id, service_id, department_id, status, priority, classification_confidence, submitted_at)
  values ('SETUX-DEMO-0002', demo_user, scholarship_service, education, 'READY_FOR_ASSIGNMENT', 'NORMAL', 91.00, now() - interval '5 days')
  on conflict (application_number) do update set status = excluded.status, priority = excluded.priority;
  select id into scholarship_app from public.applications where application_number = 'SETUX-DEMO-0002';

  insert into public.applications (application_number, user_id, service_id, department_id, assigned_officer_id, status, priority, classification_confidence, submitted_at)
  values ('SETUX-DEMO-0003', demo_user, pension_service, welfare, demo_officer, 'COMPLETED', 'LOW', 98.00, now() - interval '12 days')
  on conflict (application_number) do update set assigned_officer_id = excluded.assigned_officer_id, status = excluded.status, priority = excluded.priority;
  select id into pension_app from public.applications where application_number = 'SETUX-DEMO-0003';

  insert into public.application_extracted_data (application_id, extracted_json, ocr_text, confidence)
  values (income_app, '{"name":"Rahul Sharma","address":"Ludhiana, Punjab","annual_income":"240000","date_of_birth":"1994-02-18"}', 'Rahul Sharma, Ludhiana, Punjab, annual income 240000', 96.00),
         (scholarship_app, '{"name":"Rahul Sharma","institution":"Government College Ludhiana","course":"B.Com"}', 'Rahul Sharma, Government College Ludhiana, B.Com', 91.00),
         (pension_app, '{"name":"Rahul Sharma","address":"Ludhiana, Punjab","date_of_birth":"1958-07-11"}', 'Rahul Sharma, Ludhiana, Punjab', 98.00)
       on conflict (application_id) do update set extracted_json = excluded.extracted_json, ocr_text = excluded.ocr_text, confidence = excluded.confidence;

  insert into public.application_validation_results (application_id, is_valid, missing_fields, missing_documents, warnings)
  values (income_app, true, '[]', '[]', '["Final eligibility decision remains with officer"]'),
         (scholarship_app, true, '[]', '[]', '[]'),
         (pension_app, true, '[]', '[]', '[]')
       on conflict (application_id) do update set is_valid = excluded.is_valid, missing_fields = excluded.missing_fields, missing_documents = excluded.missing_documents, warnings = excluded.warnings;

  insert into public.officer_assignments (application_id, officer_id, assigned_by, reason)
  values (income_app, demo_officer, demo_admin, 'Correct department and lowest active workload'),
         (pension_app, demo_officer, demo_admin, 'Correct department and relevant service')
       on conflict (application_id, officer_id) do update set assigned_by = excluded.assigned_by, reason = excluded.reason;

  insert into public.application_events (application_id, event_type, description, created_by)
  values (income_app, 'APPLICATION_SUBMITTED', 'Application submitted by citizen', demo_user),
         (income_app, 'AI_CASE_PREPARED', 'Information extracted and validation completed', demo_admin),
         (income_app, 'OFFICER_ASSIGNED', 'Assigned to Ananya Mehta', demo_admin),
         (income_app, 'UNDER_REVIEW', 'Officer began review', demo_officer),
         (scholarship_app, 'APPLICATION_SUBMITTED', 'Application submitted by citizen', demo_user),
         (scholarship_app, 'READY_FOR_ASSIGNMENT', 'Validation completed and awaiting assignment', demo_admin),
         (pension_app, 'APPLICATION_SUBMITTED', 'Application submitted by citizen', demo_user),
         (pension_app, 'APPLICATION_COMPLETED', 'Application completed by officer', demo_officer)
  on conflict do nothing;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (demo_admin, 'DEMO_DATA_SEEDED', 'APPLICATION', income_app, '{"source":"seed_demo"}'),
         (demo_admin, 'DEMO_DATA_SEEDED', 'APPLICATION', scholarship_app, '{"source":"seed_demo"}'),
         (demo_admin, 'DEMO_DATA_SEEDED', 'APPLICATION', pension_app, '{"source":"seed_demo"}')
  on conflict do nothing;
end $$;

commit;