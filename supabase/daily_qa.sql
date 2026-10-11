-- Daily Q&A backend for the learner app and its built-in Admin Preview.
-- Schema source for setup_shared_project.sql, the normal one-file setup (which
-- appends all seed rows). If applying this source alone, run seed_daily_qa.sql
-- afterwards. Existing Auth users are shared.
-- Q&A tables/functions use the daily_qa_ prefix. This migration does not create
-- Auth users/passwords or replace the student app's existing Auth trigger.
-- Preflight before creating anything: stop if this is not the SmartPle project.
do $$
begin
  if to_regclass('public.smartple_profiles') is null then
    raise exception 'Expected public.smartple_profiles from the student app; stopped before applying the Q-A migration.';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='user_id')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='display_name')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='class')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='role') then
    raise exception 'smartple_profiles must have user_id, display_name, class, and role columns; stopped before applying the Q-A migration.';
  end if;
end;
$$;

create extension if not exists pgcrypto;

-- The existing SmartPle project owns Auth and public.smartple_profiles. Q-A
-- mirrors the existing user_id/class/name/role into a read-only Q-A profile map;
-- it does not create Auth users or store credentials.
create table if not exists public.daily_qa_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Student',
  class text not null default 'P4' check (class in ('P4','P5','P6','P7')),
  role text not null default 'student' check (role in ('student','admin')),
  synced_at timestamptz not null default now()
);

-- Import current student/admin profiles that are linked to a real Auth user.
-- Legacy rows with NULL or nonmatching user_id stay untouched in
-- smartple_profiles and are skipped until linked to a real Auth user.
-- Safe to rerun; linked profile updates refresh the Q-A mapping.
insert into public.daily_qa_profiles (user_id, display_name, class, role)
select
  p.user_id,
  coalesce(nullif(btrim(p.display_name), ''), 'Student'),
  case when p.class in ('P4','P5','P6','P7') then p.class else 'P4' end,
  case when p.role = 'admin' then 'admin' else 'student' end
from public.smartple_profiles p
where p.role in ('student','admin')
  and p.user_id is not null
  and exists (select 1 from auth.users u where u.id = p.user_id)
on conflict (user_id) do update
set display_name = excluded.display_name,
    class = excluded.class,
    role = excluded.role,
    synced_at = now();

-- Profile sync uses current-user/admin-gated RPCs below; this migration adds
-- no trigger to the existing SmartPle profile or Auth tables.

-- Q&A admin access has its own SQL-managed allowlist; client roles cannot edit it.
create table if not exists public.daily_qa_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  authorized_at timestamptz not null default now()
);
alter table public.daily_qa_admins enable row level security;
revoke all on public.daily_qa_admins from public, anon, authenticated;

-- Imported grade-specific Science Q&A; the current seed covers P4-P7.
create table if not exists public.daily_qa_questions (
  id text primary key,
  grade text not null check (grade in ('P4','P5','P6','P7')),
  subject text not null,
  topic text not null,
  sort_order integer not null,
  prompt text not null,
  answer text not null,
  source_file text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (grade, subject, sort_order)
);
create index if not exists daily_qa_question_bank_idx
  on public.daily_qa_questions (grade, subject, is_active, sort_order);

-- Limit inheritance: student override > class rule > global fallback (20 by default).
-- A value of 0 means paused. A NULL student override means inherit.
create table if not exists public.daily_qa_global_settings (
  id boolean primary key default true check (id = true),
  target_per_day integer not null default 20 check (target_per_day between 0 and 500),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
insert into public.daily_qa_global_settings (id, target_per_day)
values (true, 20)
on conflict (id) do nothing;

create table if not exists public.daily_qa_class_settings (
  class_name text primary key check (class_name in ('P4','P5','P6','P7')),
  target_per_day integer not null check (target_per_day between 0 and 500),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_qa_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  target_per_day integer check (target_per_day is null or target_per_day between 0 and 500),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

-- One active set per learner. A set keeps its original target if an admin edits
-- a limit while it is in progress; the new effective limit applies to the next set.
create table if not exists public.daily_qa_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  set_number integer not null,
  assigned_date date not null,
  requested_target integer not null check (requested_target between 1 and 500),
  target_count integer not null check (target_count between 1 and 500),
  completed_count integer not null default 0 check (completed_count between 0 and 500),
  status text not null default 'active' check (status in ('active','completed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (user_id, set_number)
);
create index if not exists daily_qa_assignment_user_idx
  on public.daily_qa_assignments (user_id, set_number desc);
create unique index if not exists daily_qa_one_active_set_per_student_idx
  on public.daily_qa_assignments (user_id) where status = 'active';

create table if not exists public.daily_qa_assignment_items (
  assignment_id uuid not null references public.daily_qa_assignments(id) on delete cascade,
  question_id text not null references public.daily_qa_questions(id) on delete restrict,
  position integer not null,
  completed_at timestamptz,
  primary key (assignment_id, question_id),
  unique (assignment_id, position)
);
create index if not exists daily_qa_items_assignment_idx
  on public.daily_qa_assignment_items (assignment_id, position);

-- Q&A admin authority requires a SQL-managed allowlist entry and an existing
-- SmartPle admin profile. Clients cannot read or modify daily_qa_admins.
create or replace function public.daily_qa_is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.daily_qa_admins a
    join public.daily_qa_profiles p on p.user_id = a.user_id
    join public.smartple_profiles s on s.user_id = a.user_id
    where a.user_id = auth.uid() and p.role = 'admin' and s.role = 'admin'
  );
$$;
revoke all on function public.daily_qa_is_admin() from public, anon;
grant execute on function public.daily_qa_is_admin() to authenticated;

-- Sync only the caller's SmartPle profile after sign-in. It cannot write another
-- user's Q-A profile, and the Q-A mapping table remains read-only to clients.
create or replace function public.daily_qa_sync_my_profile()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile public.smartple_profiles%rowtype;
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'Sign in is required.';
  end if;
  select * into v_profile from public.smartple_profiles where user_id = v_user;
  if not found or v_profile.role not in ('student','admin') then
    raise exception using errcode = '42501', message = 'A valid SmartPle profile is required.';
  end if;
  insert into public.daily_qa_profiles (user_id, display_name, class, role, synced_at)
  values (
    v_user,
    coalesce(nullif(btrim(v_profile.display_name), ''), 'Student'),
    case when v_profile.class in ('P4','P5','P6','P7') then v_profile.class else 'P4' end,
    v_profile.role,
    now()
  )
  on conflict (user_id) do update
  set display_name = excluded.display_name,
      class = excluded.class,
      role = excluded.role,
      synced_at = now();
end;
$$;
revoke all on function public.daily_qa_sync_my_profile() from public, anon;
grant execute on function public.daily_qa_sync_my_profile() to authenticated;

-- Admin-only roster sync imports students who were added since the initial
-- backfill. Admin authorization uses the protected daily_qa_admins allowlist.
create or replace function public.daily_qa_sync_profiles()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.daily_qa_is_admin() then
    raise exception using errcode = '42501', message = 'Q-A administrator access is required.';
  end if;
  insert into public.daily_qa_profiles (user_id, display_name, class, role, synced_at)
  select
    p.user_id,
    coalesce(nullif(btrim(p.display_name), ''), 'Student'),
    case when p.class in ('P4','P5','P6','P7') then p.class else 'P4' end,
    p.role,
    now()
  from public.smartple_profiles p
  where p.role in ('student','admin')
    and p.user_id is not null
    and exists (select 1 from auth.users u where u.id = p.user_id)
  on conflict (user_id) do update
  set display_name = excluded.display_name,
      class = excluded.class,
      role = excluded.role,
      synced_at = now();
end;
$$;
revoke all on function public.daily_qa_sync_profiles() from public, anon;
grant execute on function public.daily_qa_sync_profiles() to authenticated;

-- Resolve the signed-in student's effective daily target. Internal helper only.
create or replace function public.daily_qa_effective_target()
returns integer
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select s.target_per_day from public.daily_qa_settings s where s.user_id = auth.uid()),
    (select c.target_per_day
       from public.daily_qa_profiles p
       join public.daily_qa_class_settings c on c.class_name = p.class
      where p.user_id = auth.uid()),
    (select g.target_per_day from public.daily_qa_global_settings g where g.id = true),
    20
  );
$$;
revoke all on function public.daily_qa_effective_target() from public, anon, authenticated;

-- RLS and least-privilege grants apply only to Q-A tables. The existing
-- SmartPle profile table, its grants, policies, and Auth trigger are not altered.
alter table public.daily_qa_profiles enable row level security;
alter table public.daily_qa_questions enable row level security;
alter table public.daily_qa_global_settings enable row level security;
alter table public.daily_qa_class_settings enable row level security;
alter table public.daily_qa_settings enable row level security;
alter table public.daily_qa_assignments enable row level security;
alter table public.daily_qa_assignment_items enable row level security;

revoke all on public.daily_qa_profiles from public, anon, authenticated;
revoke all on public.daily_qa_questions from public, anon, authenticated;
revoke all on public.daily_qa_global_settings from public, anon, authenticated;
revoke all on public.daily_qa_class_settings from public, anon, authenticated;
revoke all on public.daily_qa_settings from public, anon, authenticated;
revoke all on public.daily_qa_assignments from public, anon, authenticated;
revoke all on public.daily_qa_assignment_items from public, anon, authenticated;

grant select on public.daily_qa_profiles to authenticated;
grant select on public.daily_qa_questions to authenticated;
grant select, insert, update, delete on public.daily_qa_global_settings to authenticated;
grant select, insert, update, delete on public.daily_qa_class_settings to authenticated;
grant select, insert, update, delete on public.daily_qa_settings to authenticated;
grant select on public.daily_qa_assignments to authenticated;
grant select on public.daily_qa_assignment_items to authenticated;

-- Q-A profiles are read-only to clients: learners read self, Q-A admins read all.
drop policy if exists daily_qa_profiles_self_or_admin_read on public.daily_qa_profiles;
create policy daily_qa_profiles_self_or_admin_read on public.daily_qa_profiles
  for select to authenticated using (user_id = auth.uid() or public.daily_qa_is_admin());

-- Question bank is readable to signed-in users; only admins manage it.
drop policy if exists daily_qa_questions_read on public.daily_qa_questions;
create policy daily_qa_questions_read on public.daily_qa_questions
  for select to authenticated using (is_active or public.daily_qa_is_admin());
drop policy if exists daily_qa_questions_admin on public.daily_qa_questions;
create policy daily_qa_questions_admin on public.daily_qa_questions
  for all to authenticated using (public.daily_qa_is_admin())
  with check (public.daily_qa_is_admin());

-- All signed-in users can read shared global/class defaults; only admins can change them.
drop policy if exists daily_qa_global_settings_read on public.daily_qa_global_settings;
create policy daily_qa_global_settings_read on public.daily_qa_global_settings
  for select to authenticated using (true);
drop policy if exists daily_qa_global_settings_admin on public.daily_qa_global_settings;
create policy daily_qa_global_settings_admin on public.daily_qa_global_settings
  for all to authenticated using (public.daily_qa_is_admin())
  with check (public.daily_qa_is_admin());

drop policy if exists daily_qa_class_settings_read on public.daily_qa_class_settings;
create policy daily_qa_class_settings_read on public.daily_qa_class_settings
  for select to authenticated using (true);
drop policy if exists daily_qa_class_settings_admin on public.daily_qa_class_settings;
create policy daily_qa_class_settings_admin on public.daily_qa_class_settings
  for all to authenticated using (public.daily_qa_is_admin())
  with check (public.daily_qa_is_admin());

-- Students can read only their own personal override; admins can read/write all.
drop policy if exists daily_qa_settings_self_read on public.daily_qa_settings;
create policy daily_qa_settings_self_read on public.daily_qa_settings
  for select to authenticated using (user_id = auth.uid() or public.daily_qa_is_admin());
drop policy if exists daily_qa_settings_admin on public.daily_qa_settings;
create policy daily_qa_settings_admin on public.daily_qa_settings
  for all to authenticated using (public.daily_qa_is_admin())
  with check (public.daily_qa_is_admin());

-- Learners can read only their own progress; admins can read/manage all progress.
drop policy if exists daily_qa_assignments_self_read on public.daily_qa_assignments;
create policy daily_qa_assignments_self_read on public.daily_qa_assignments
  for select to authenticated using (user_id = auth.uid() or public.daily_qa_is_admin());
drop policy if exists daily_qa_assignments_admin_all on public.daily_qa_assignments;
create policy daily_qa_assignments_admin_all on public.daily_qa_assignments
  for all to authenticated using (public.daily_qa_is_admin())
  with check (public.daily_qa_is_admin());

drop policy if exists daily_qa_items_self_read on public.daily_qa_assignment_items;
create policy daily_qa_items_self_read on public.daily_qa_assignment_items
  for select to authenticated using (
    exists (
      select 1 from public.daily_qa_assignments a
      where a.id = assignment_id and (a.user_id = auth.uid() or public.daily_qa_is_admin())
    )
  );
drop policy if exists daily_qa_items_admin_all on public.daily_qa_assignment_items;
create policy daily_qa_items_admin_all on public.daily_qa_assignment_items
  for all to authenticated using (public.daily_qa_is_admin())
  with check (public.daily_qa_is_admin());

-- Internal helper returns a set in question order. Clients call only checked RPCs.
create or replace function public.daily_qa_assignment_payload(p_assignment_id uuid, p_status text default null)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'status', coalesce(p_status, a.status),
    'assignment_id', a.id,
    'set_number', a.set_number,
    'assigned_date', a.assigned_date,
    'target', a.target_count,
    'requested_target', a.requested_target,
    'completed_count', a.completed_count,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'question_id', q.id,
        'position', i.position,
        'grade', q.grade,
        'subject', q.subject,
        'topic', q.topic,
        'question', q.prompt,
        'answer', q.answer,
        'completed_at', i.completed_at
      ) order by i.position)
      from public.daily_qa_assignment_items i
      join public.daily_qa_questions q on q.id = i.question_id
      where i.assignment_id = a.id
    ), '[]'::jsonb)
  )
  from public.daily_qa_assignments a
  where a.id = p_assignment_id;
$$;
revoke all on function public.daily_qa_assignment_payload(uuid, text) from public, anon, authenticated;

create or replace function public.daily_qa_get_or_start_set()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Africa/Kampala')::date;
  v_target integer;
  v_grade text;
  v_subject text := 'Science';
  v_profile public.daily_qa_profiles%rowtype;
  v_assignment public.daily_qa_assignments%rowtype;
  v_available integer := 0;
  v_take integer := 0;
  v_set_number integer := 1;
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'Sign in is required.';
  end if;

  perform public.daily_qa_sync_my_profile();
  select * into v_profile from public.daily_qa_profiles where user_id = v_user;
  if not found or v_profile.role <> 'student' then
    raise exception using errcode = '42501', message = 'A student profile is required.';
  end if;

  v_target := public.daily_qa_effective_target();
  if v_target = 0 then
    return jsonb_build_object(
      'status', 'paused', 'target', 0,
      'message', 'Daily Q&A is paused by your admin.'
    );
  end if;
  v_grade := coalesce(v_profile.class, 'P4');

  perform pg_advisory_xact_lock(hashtext(v_user::text));

  -- Always resume an unfinished set, even if its assigned date has passed.
  select * into v_assignment
  from public.daily_qa_assignments
  where user_id = v_user and status = 'active'
  order by set_number desc
  limit 1
  for update;
  if found then
    return public.daily_qa_assignment_payload(v_assignment.id, 'active');
  end if;

  -- A completed set counts for its assigned day. Never stack another set that day.
  select * into v_assignment
  from public.daily_qa_assignments
  where user_id = v_user
  order by set_number desc
  limit 1;
  if found and v_assignment.status = 'completed' and v_assignment.assigned_date >= v_today then
    return public.daily_qa_assignment_payload(v_assignment.id, 'complete');
  end if;

  -- Do not repeat a question for the same learner.
  select count(*) into v_available
  from public.daily_qa_questions q
  where q.is_active and q.grade = v_grade and q.subject = v_subject
    and not exists (
      select 1 from public.daily_qa_assignment_items i
      join public.daily_qa_assignments a on a.id = i.assignment_id
      where a.user_id = v_user and i.question_id = q.id
    );

  if v_available = 0 then
    return jsonb_build_object(
      'status', 'exhausted', 'target', v_target, 'grade', v_grade, 'subject', v_subject,
      'message', 'The question bank is exhausted or not yet available for this class.'
    );
  end if;

  v_take := least(v_target, v_available);
  select coalesce(max(set_number), 0) + 1 into v_set_number
  from public.daily_qa_assignments where user_id = v_user;

  insert into public.daily_qa_assignments (
    user_id, set_number, assigned_date, requested_target, target_count, status
  ) values (v_user, v_set_number, v_today, v_target, v_take, 'active')
  returning * into v_assignment;

  insert into public.daily_qa_assignment_items (assignment_id, question_id, position)
  select v_assignment.id, selected.id,
         row_number() over (order by selected.sort_order, selected.id)::integer
  from (
    select q.id, q.sort_order from public.daily_qa_questions q
    where q.is_active and q.grade = v_grade and q.subject = v_subject
      and not exists (
        select 1 from public.daily_qa_assignment_items i
        join public.daily_qa_assignments a on a.id = i.assignment_id
        where a.user_id = v_user and i.question_id = q.id
      )
    order by q.sort_order, q.id limit v_take
  ) as selected;

  return public.daily_qa_assignment_payload(v_assignment.id, 'active');
end;
$$;

create or replace function public.daily_qa_complete_item(p_assignment_id uuid, p_question_id text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_assignment public.daily_qa_assignments%rowtype;
  v_done integer;
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'Sign in is required.';
  end if;
  if public.daily_qa_effective_target() = 0 then
    raise exception using errcode = '42501', message = 'Daily Q&A is paused by your admin.';
  end if;

  select * into v_assignment
  from public.daily_qa_assignments
  where id = p_assignment_id and user_id = v_user and status = 'active'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'This question set is no longer active.';
  end if;

  update public.daily_qa_assignment_items
  set completed_at = coalesce(completed_at, now())
  where assignment_id = p_assignment_id and question_id = p_question_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Question does not belong to this set.';
  end if;

  select (count(*) filter (where completed_at is not null))::integer into v_done
  from public.daily_qa_assignment_items where assignment_id = p_assignment_id;

  update public.daily_qa_assignments
  set completed_count = v_done,
      status = case when v_done >= target_count then 'completed' else 'active' end,
      completed_at = case when v_done >= target_count then coalesce(completed_at, now()) else null end
  where id = p_assignment_id returning * into v_assignment;

  return public.daily_qa_assignment_payload(
    p_assignment_id,
    case when v_assignment.status = 'completed' then 'complete' else 'active' end
  );
end;
$$;

revoke all on function public.daily_qa_get_or_start_set() from public, anon;
revoke all on function public.daily_qa_complete_item(uuid, text) from public, anon;
grant execute on function public.daily_qa_get_or_start_set() to authenticated;
grant execute on function public.daily_qa_complete_item(uuid, text) to authenticated;

-- Existing SmartPle Auth accounts are reused; no duplicate Q&A account is needed.
-- After this setup succeeds, run authorize_qa_admin.sql, then the separate
-- secure_smartple_profiles.sql patch, then verify_daily_qa.sql. The profile
-- security patch is separate so the existing app can be reviewed before changes.
