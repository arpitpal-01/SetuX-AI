# SetuX AI

SetuX AI is an MVP dashboard for intelligent government-service workflow automation. The current runnable shell demonstrates the citizen, officer, and administrator workflows with local demo data, while the Supabase migration defines the production data and security boundary.

## Run locally

1. Install Node.js 20 or newer.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and add your Supabase project URL and anonymous key.
4. Run `npm run dev`.

Routes:

- `/` or `/dashboard/user`: citizen overview
- `/dashboard/user/new-application`: four-step application flow
- `/dashboard/officer`: AI case preparation view
- `/dashboard/admin`: operations analytics

## Supabase setup

Run `supabase/migrations/001_setux_schema.sql` in the Supabase SQL editor or through the Supabase CLI. The migration creates the relational model, role helpers, application transition guard, RLS policies, private document bucket, signup profile trigger, and seed departments/services.

The document path convention is `<user-id>/<application-id>/<filename>`. The storage policy checks the application row before allowing a user, assigned officer, or admin to read a document.

## Demo accounts and data

For a local presentation, create these accounts through `/auth` first:

| Role | Email | Password |
| --- | --- | --- |
| Citizen | `demo.citizen@setux.test` | `SetuXDemo2026!` |
| Officer | `demo.officer@setux.test` | `SetuXDemo2026!` |
| Admin | `demo.admin@setux.test` | `SetuXDemo2026!` |

Then run `supabase/seed_demo.sql` in the Supabase SQL Editor. It promotes the accounts, assigns departments, and adds three realistic applications with extracted data, validation results, assignments, timeline events, and audit records. The script uses `on conflict` guards and does not delete existing data.

## Government service catalog

Run `supabase/migrations/002_government_service_catalog.sql` after the first migration. It adds the requested ten services: Birth, Caste, Income, Residential/Domicile, Death, Disability, Character, Legal Heir, Ration Card, and Senior Citizen Certificate/ID. It also adds Revenue, Civil Registration, Social Welfare, Health, Police, and Food & Civil Supplies departments plus official-link labels and service requirements.

For a full department demo, create two Auth users for each department using the emails listed in that migration, then rerun it. The updates promote those profiles to `OFFICER` and assign their departments. Auth user creation must remain in Supabase Auth; the public browser client must never receive a service-role key.

## Production follow-up

The visual MVP uses demo records so it is inspectable without credentials. The next integration slice should replace those records with Supabase Auth/session state and server-side operations for OCR, extraction, classification, validation, assignment, and audit logging. Keep service-role credentials exclusively in Edge Functions or other trusted server execution.