-- Government service catalog for the SetuX demo.
-- Safe to run after 001_setux_schema.sql. Existing service rows are updated, not deleted.

alter table public.services add column if not exists official_link text;

insert into public.departments (name, description) values
  ('Revenue Department', 'Certificates and district administration services'),
  ('Civil Registration', 'Birth and death registration services'),
  ('Social Welfare', 'Welfare and senior citizen services'),
  ('Health Department', 'Health and disability certification services'),
  ('Police Department', 'Character and verification services'),
  ('Food & Civil Supplies', 'Ration and essential supplies services')
on conflict (name) do update set description = excluded.description;

with catalog(name, department, description, official_link, required_documents, required_fields) as (
  values
    ('Birth Certificate', 'Civil Registration', 'Birth registration and certified copy', 'Birth & Death Services', '["Hospital Record","Identity Proof"]'::jsonb, '["Name","Date of Birth","Place of Birth"]'::jsonb),
    ('Caste Certificate', 'Revenue Department', 'Caste and community certificate', 'Caste Certificate Services', '["Identity Proof","Address Proof","Supporting Certificate"]'::jsonb, '["Name","Address","Caste Category"]'::jsonb),
    ('Income Certificate', 'Revenue Department', 'Proof of annual income', 'Income Certificate Services', '["Identity Proof","Address Proof","Income Proof"]'::jsonb, '["Name","Address","Annual Income"]'::jsonb),
    ('Residential / Domicile Certificate', 'Revenue Department', 'Proof of residence or domicile', 'Domicile Services', '["Identity Proof","Address Proof"]'::jsonb, '["Name","Address","Years of Residence"]'::jsonb),
    ('Death Certificate', 'Civil Registration', 'Death registration and certified copy', 'Death Certificate Services', '["Medical Record","Identity Proof"]'::jsonb, '["Name","Date of Death","Place of Death"]'::jsonb),
    ('Disability Certificate', 'Health Department', 'Disability assessment and certification', 'Disability Services', '["Identity Proof","Medical Report"]'::jsonb, '["Name","Disability Type","Disability Percentage"]'::jsonb),
    ('Character Certificate', 'Police Department', 'Police character and verification certificate', 'Character Certificate Services', '["Identity Proof","Address Proof"]'::jsonb, '["Name","Address","Purpose"]'::jsonb),
    ('Legal Heir Certificate', 'Revenue Department', 'Legal heir verification certificate', 'Legal Heir Services', '["Identity Proof","Death Certificate","Family Proof"]'::jsonb, '["Name","Deceased Name","Relationship"]'::jsonb),
    ('Ration Card Application', 'Food & Civil Supplies', 'New or updated ration card application', 'Government Services Portal', '["Identity Proof","Address Proof","Family Details"]'::jsonb, '["Head of Family","Address","Family Members"]'::jsonb),
    ('Senior Citizen Certificate / ID', 'Social Welfare', 'Senior citizen certificate and identity card', 'Government Services Portal', '["Identity Proof","Age Proof","Address Proof"]'::jsonb, '["Name","Date of Birth","Address"]'::jsonb)
)
insert into public.services (department_id, name, description, official_link, required_documents, required_fields)
select d.id, c.name, c.description, c.official_link, c.required_documents, c.required_fields
from catalog c join public.departments d on d.name = c.department
on conflict (name) do update set department_id = excluded.department_id, description = excluded.description, official_link = excluded.official_link, required_documents = excluded.required_documents, required_fields = excluded.required_fields;

-- Create these Auth users through /auth before running the optional officer promotion updates:
-- revenue.1@setux.test, revenue.2@setux.test
-- registration.1@setux.test, registration.2@setux.test
-- welfare.1@setux.test, welfare.2@setux.test
-- health.1@setux.test, health.2@setux.test
-- police.1@setux.test, police.2@setux.test
-- supplies.1@setux.test, supplies.2@setux.test
-- Then assign them securely as OFFICER profiles using the Supabase SQL editor.

update public.profiles p set role = 'OFFICER', department_id = d.id
from public.departments d
where p.email in ('revenue.1@setux.test', 'revenue.2@setux.test') and d.name = 'Revenue Department';
update public.profiles p set role = 'OFFICER', department_id = d.id
from public.departments d
where p.email in ('registration.1@setux.test', 'registration.2@setux.test') and d.name = 'Civil Registration';
update public.profiles p set role = 'OFFICER', department_id = d.id
from public.departments d
where p.email in ('welfare.1@setux.test', 'welfare.2@setux.test') and d.name = 'Social Welfare';
update public.profiles p set role = 'OFFICER', department_id = d.id
from public.departments d
where p.email in ('health.1@setux.test', 'health.2@setux.test') and d.name = 'Health Department';
update public.profiles p set role = 'OFFICER', department_id = d.id
from public.departments d
where p.email in ('police.1@setux.test', 'police.2@setux.test') and d.name = 'Police Department';
update public.profiles p set role = 'OFFICER', department_id = d.id
from public.departments d
where p.email in ('supplies.1@setux.test', 'supplies.2@setux.test') and d.name = 'Food & Civil Supplies';
