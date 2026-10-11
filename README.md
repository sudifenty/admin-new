# SmartPle PLE Science — Daily Q&A

This is the single-file Q&A application, with **Open student preview** and **Open admin preview** built into the landing page. The built-in admin screen is the admin interface for this project. The separate `admin-new` app is only a read-only feature/UI reference; its mock roster and storage are not used here, and it is not the admin interface being adopted.

## Files

```text
index.html                       Student flow, built-in admin panel, and embedded Q&A bank
manifest.webmanifest              Installable PWA name, scope, colors, and icons
service-worker.js                 Offline app-shell cache; never caches Supabase/private API traffic
icons/                            192px, 512px, and Apple touch icons
content/question_bank.json       Canonical, ordered P4–P7 Science Q&A used by the app
content/question_order.csv       Question-only grade/topic/order index; no answers
supabase/setup_shared_project.sql Paste-ready schema plus all 660 questions for the existing SmartPle project
supabase/setup_sql_copy.html     Visible SQL panel with copy/download controls
supabase/secure_smartple_profiles.sql Restricts shared profile access while preserving student/admin reads
supabase/secure_profiles_copy.html    Visible profile-security patch with copy/download controls
supabase/daily_qa.sql            Schema source used to generate the combined setup file
supabase/authorize_qa_admin.sql  Maps an existing SmartPle admin to the protected Q-A allowlist
supabase/seed_daily_qa.sql       Canonical 660 ordered P4–P7 Science Q&A seed
supabase/verify_daily_qa.sql     Read-only checks for shared profiles, policies/RLS/RPCs, and bank counts
supabase/verify_sql_copy.html    Visible verifier panel with copy/download controls
tools/build_daily_qa_assets.py   Rebuilds seed, combined setup SQL/copy panel, CSV, and embedded HTML data
.env.example                     Reference for browser connection fields; not loaded at runtime
```

## Question-bank scope and order

The Q&A wording was copied from the existing app data, not newly authored or shuffled. The P4 source bank remains in its original order. P5, P6, and P7 use the existing short-answer revision banks in their original topic/question order and retain their source IDs. The resulting bank has **P4: 160, P5: 180, P6: 200, P7: 120** Science questions (660 total). `content/question_order.csv` is the question-only list for checking grade and order; the learner experience still shows each existing question with its answer together, as guided revision.

If you edit the canonical JSON while preserving its sequence and per-grade numbering, regenerate the seed, one-file paste-ready setup, question-only CSV, and embedded HTML data with:

```bash
python tools/build_daily_qa_assets.py
```

## Shared Supabase Auth and setup

Q-A is configured to use the **same Supabase project and Auth accounts as the existing student app**. Each student signs in with the same account; the migration does not create duplicate Auth users or copy passwords. It maintains a read-only `daily_qa_profiles` mapping keyed by the same Auth `user_id`, populated from `smartple_profiles`. Existing accounts with a non-NULL `smartple_profiles.user_id` are backfilled at setup; a student syncs only their own profile at sign-in, and the Q-A admin roster refresh syncs linked new/current student profiles. Legacy source rows with NULL or nonmatching `user_id` values are left untouched and skipped because they cannot be matched to a Supabase Auth account; they remain unavailable in Q-A until linked to a real Auth user. These are guarded RPCs, not triggers: the Q-A setup SQL leaves the existing Auth signup trigger and SmartPle profile policies/grants untouched. Because the current `smartple_profiles` access is overly broad, apply the separate, reviewable profile-security patch before live student use. The Q-A mapping is metadata only, not another login.

Use these files in the existing student app project’s SQL Editor:

1. Copy/paste the **entire** `supabase/setup_shared_project.sql` and run it. It includes the additive schema, profile mapping, RLS/RPCs, and all 660 seed rows. It expects `smartple_profiles` with `user_id`, `display_name`, `class`, and `role`; it does not replace the Auth signup trigger or alter SmartPle profile grants/policies.
2. Run `supabase/authorize_qa_admin.sql` as project owner. It authorizes the sole existing SmartPle admin linked to Auth; it stops without changes if zero or multiple linked admins are found. It adds no Auth account and stores no password.
3. Review and run `supabase/secure_smartple_profiles.sql` as project owner. It removes the reported allow-all profile policies and browser grants, then enables student-self/admin-managed access. It stops if it finds unexpected policies; it does not alter profile rows.
4. Run `supabase/verify_daily_qa.sql` for read-only checks of shared profiles, the protected admin mapping, Q&A policies/RLS/RPCs, global target row, and minimum per-grade counts.

`daily_qa.sql` and `seed_daily_qa.sql` remain the separate source files used to build the combined paste-ready setup.

Do not run an older Daily Q&A draft in place of these files or create separate student Auth accounts for Q-A. Before learner sign-in, check that each student's `smartple_profiles.class` is `P4`, `P5`, `P6`, or `P7`; a NULL class is treated as P4. Q-A admin access requires both an existing SmartPle profile with `role = 'admin'` and a matching row in `daily_qa_admins`. That allowlist is not accessible through the client API.

## Live connection and credentials

This is a static HTML app, so it does **not** load `.env` files at runtime. It is preconfigured with the student app's Supabase project URL and publishable key that you provided; you can review or change them under **Connection / SQL**. Any saved overrides are stored in this browser's local storage. The publishable key is intended for client use; never enter a service-role/secret key, and never store passwords in the app or database. Student and admin passwords are handled by the existing Supabase Auth project.

Serve the file from an `http(s)` site for live requests; some browsers block API requests from a `file://` URL. Demo previews work locally without a Supabase connection.

## PWA install and offline behavior

The app includes a web manifest, app icons, an install prompt where supported, and a service worker. Serve it from **HTTPS** (or `localhost` for testing); PWA installation/service workers do not work from `file://`. On iPhone/iPad, use **Share → Add to Home Screen**.

After the first visit, the service worker can reopen the app shell and local demo offline. It caches same-origin static files/icons; because the demo bank is embedded in `index.html`, that embedded Q&A bank is included in the app-shell cache. It does **not** cache Supabase Auth/API responses or live learner progress. **Live sign-in and progress saving need internet**; offline actions are not queued for later sync.

## Behavior

- Guided revision: one question at a time, with its answer/explanation shown together. **NEXT** marks it studied and advances; there are no answer prompts, options, grading, or scores.
- The built-in Admin Preview controls global, P4–P7 class, and individual student daily targets. Presets are **0, 5, 10, 20, and 50**, with a custom whole-number value from 0 to 500. Precedence is **student override → class rule → global default**; default is 20. A student-level 0 pauses that student; higher-priority rules override lower-priority rules.
- A class rule can be removed to inherit the global default; a student override can be cleared to inherit the class/global target. The student list searches name/class and displays each learner's effective target, its source, and Q&A status.
- Dashboard cards show the loaded student count and global default. Selecting a student opens their limit editor and latest Q&A set with question-level studied status. The separate `admin-new` demo's mock roster and localStorage are not used by the built-in panel.
- Active sets resume; a completed set is not stacked with another on the same day; a learner does not receive a repeated question after exhausting their class bank.

## Validation status

Static checks confirmed all 660 items, exact source wording/order, per-grade counts, the questions-only CSV, generated seed, combined setup SQL, and embedded HTML copies. The inline JavaScript, service worker, PWA manifest, icon assets, required DOM IDs, and local asset responses were checked. The owner reports the combined SQL setup and admin authorization succeeded. The read-only verifier stopped because the existing `smartple_profiles` table has RLS disabled and permissive grants/policies. `secure_smartple_profiles.sql` is prepared but has not been applied; student login, full verification, and device-level PWA installation/offline behavior remain untested.
