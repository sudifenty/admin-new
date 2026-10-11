-- Read-only post-setup checks for Q-A tables in the existing SmartPle project.
-- Run after setup_shared_project.sql, then authorize_qa_admin.sql, in that order.
-- This script does not modify data.

do $$
declare
  v_table text;
  v_relation oid;
  v_rls boolean;
  v_policy_count integer;
  v_p4 bigint;
  v_p5 bigint;
  v_p6 bigint;
  v_p7 bigint;
  v_total bigint;
  v_missing_profiles bigint;
  v_auth_without_smartple bigint;
  v_unlinked_profiles bigint;
begin
  -- Existing SmartPle profile source expected by the guarded Q-A sync RPCs.
  if to_regclass('public.smartple_profiles') is null then
    raise exception 'Missing public.smartple_profiles. Stop: this setup expects the student app schema.';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='user_id')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='display_name')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='class')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='smartple_profiles' and column_name='role') then
    raise exception 'smartple_profiles must include user_id, display_name, class, and role columns.';
  end if;
  select c.relrowsecurity into v_rls from pg_catalog.pg_class c where c.oid = 'public.smartple_profiles'::regclass;
  if not coalesce(v_rls, false) then
    raise exception 'Row-level security is not enabled on public.smartple_profiles. Apply secure_smartple_profiles.sql first.';
  end if;
  if to_regprocedure('public.smartple_profiles_admin_for_rls()') is null then
    raise exception 'Missing scoped SmartPle admin helper public.smartple_profiles_admin_for_rls().';
  end if;
  if not exists (
       select 1 from pg_catalog.pg_policies
       where schemaname='public' and tablename='smartple_profiles'
         and policyname='smartple_profiles_self_select' and cmd='SELECT'
     )
     or not exists (
       select 1 from pg_catalog.pg_policies
       where schemaname='public' and tablename='smartple_profiles'
         and policyname='smartple_profiles_admin_update' and cmd='UPDATE'
     ) then
    raise exception 'Expected scoped student-read/admin-update policies on public.smartple_profiles; apply secure_smartple_profiles.sql.';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='public' and tablename='smartple_profiles'
      and policyname in ('allow all','allow all profiles')
  ) then
    raise exception 'A broad allow-all policy remains on public.smartple_profiles.';
  end if;
  if has_table_privilege('anon','public.smartple_profiles','select')
     or has_table_privilege('anon','public.smartple_profiles','insert')
     or has_table_privilege('anon','public.smartple_profiles','update')
     or has_table_privilege('anon','public.smartple_profiles','delete') then
    raise exception 'The anon role still has direct privileges on public.smartple_profiles.';
  end if;
  if has_table_privilege('authenticated','public.smartple_profiles','insert')
     or has_table_privilege('authenticated','public.smartple_profiles','delete') then
    raise exception 'Authenticated clients must not directly insert/delete public.smartple_profiles.';
  end if;

  v_auth_without_smartple := (
    select count(*) from auth.users u
    left join public.smartple_profiles p on p.user_id = u.id
    where p.user_id is null
  );
  if v_auth_without_smartple > 0 then
    raise notice '% Auth user(s) have no SmartPle profile row.', v_auth_without_smartple;
  end if;

  select count(*) into v_unlinked_profiles
  from public.smartple_profiles s
  where s.role in ('student','admin')
    and (s.user_id is null or not exists (select 1 from auth.users u where u.id = s.user_id));
  if v_unlinked_profiles > 0 then
    raise notice '% legacy SmartPle profile(s) have no matching Auth user_id; they were skipped and cannot sign in through Q-A until linked to a real Auth user.', v_unlinked_profiles;
  end if;

  if to_regprocedure('public.daily_qa_sync_my_profile()') is null then
    raise exception 'Missing caller-scoped profile sync RPC public.daily_qa_sync_my_profile().';
  end if;
  if to_regprocedure('public.daily_qa_sync_profiles()') is null then
    raise exception 'Missing admin-only roster sync RPC public.daily_qa_sync_profiles().';
  end if;

  if to_regclass('public.daily_qa_profiles') is null then
    raise exception 'Missing public.daily_qa_profiles mapping table.';
  end if;

  v_missing_profiles := (
    select count(*)
    from public.smartple_profiles s
    left join public.daily_qa_profiles q on q.user_id = s.user_id
    where s.role in ('student','admin')
      and exists (select 1 from auth.users u where u.id = s.user_id)
      and q.user_id is null
  );
  if v_missing_profiles > 0 then
    raise exception '% SmartPle profile(s) have not been mapped into Q-A profiles.', v_missing_profiles;
  end if;
  if has_table_privilege('authenticated', 'public.daily_qa_profiles', 'insert')
     or has_table_privilege('authenticated', 'public.daily_qa_profiles', 'update')
     or has_table_privilege('authenticated', 'public.daily_qa_profiles', 'delete') then
    raise exception 'Authenticated clients must not directly write daily_qa_profiles.';
  end if;

  -- Q-A admin allowlist is only managed in SQL Editor, not through the client API.
  if to_regclass('public.daily_qa_admins') is null then
    raise exception 'Missing protected public.daily_qa_admins allowlist.';
  end if;
  select c.relrowsecurity into v_rls from pg_catalog.pg_class c where c.oid = 'public.daily_qa_admins'::regclass;
  if not coalesce(v_rls, false) then
    raise exception 'Row-level security is not enabled on public.daily_qa_admins.';
  end if;
  if has_table_privilege('authenticated', 'public.daily_qa_admins', 'select')
     or has_table_privilege('authenticated', 'public.daily_qa_admins', 'insert')
     or has_table_privilege('authenticated', 'public.daily_qa_admins', 'update')
     or has_table_privilege('authenticated', 'public.daily_qa_admins', 'delete') then
    raise exception 'Authenticated clients must not have direct privileges on daily_qa_admins.';
  end if;
  if not exists (
    select 1
    from public.daily_qa_admins a
    join public.daily_qa_profiles q on q.user_id = a.user_id
    join public.smartple_profiles s on s.user_id = a.user_id
    where q.role = 'admin' and s.role = 'admin'
  ) then
    raise exception 'No Q-A admin is authorized. Add an existing SmartPle admin to daily_qa_admins in SQL Editor.';
  end if;

  foreach v_table in array array[
    'daily_qa_profiles',
    'daily_qa_questions',
    'daily_qa_global_settings',
    'daily_qa_class_settings',
    'daily_qa_settings',
    'daily_qa_assignments',
    'daily_qa_assignment_items'
  ] loop
    v_relation := to_regclass(format('public.%I', v_table))::oid;
    if v_relation is null then
      raise exception 'Missing table public.%', v_table;
    end if;

    select c.relrowsecurity
      into v_rls
      from pg_catalog.pg_class c
     where c.oid = v_relation;
    if not coalesce(v_rls, false) then
      raise exception 'Row-level security is not enabled on public.%', v_table;
    end if;

    select count(*)
      into v_policy_count
      from pg_catalog.pg_policies p
     where p.schemaname = 'public'
       and p.tablename = v_table;
    if v_policy_count = 0 then
      raise exception 'No RLS policies found for public.%', v_table;
    end if;
  end loop;

  select count(*) into v_p4 from public.daily_qa_questions where grade = 'P4' and subject = 'Science' and is_active;
  select count(*) into v_p5 from public.daily_qa_questions where grade = 'P5' and subject = 'Science' and is_active;
  select count(*) into v_p6 from public.daily_qa_questions where grade = 'P6' and subject = 'Science' and is_active;
  select count(*) into v_p7 from public.daily_qa_questions where grade = 'P7' and subject = 'Science' and is_active;
  v_total := v_p4 + v_p5 + v_p6 + v_p7;

  if v_p4 < 160 then raise exception 'Expected at least 160 active P4 Science items; found %', v_p4; end if;
  if v_p5 < 180 then raise exception 'Expected at least 180 active P5 Science items; found %', v_p5; end if;
  if v_p6 < 200 then raise exception 'Expected at least 200 active P6 Science items; found %', v_p6; end if;
  if v_p7 < 120 then raise exception 'Expected at least 120 active P7 Science items; found %', v_p7; end if;

  if not exists (select 1 from public.daily_qa_global_settings where id = true) then
    raise exception 'The global daily-target row is missing.';
  end if;
  if to_regprocedure('public.daily_qa_is_admin()') is null then
    raise exception 'Missing Q-A admin gate public.daily_qa_is_admin().';
  end if;
  if to_regprocedure('public.daily_qa_effective_target()') is null then
    raise exception 'Missing target resolver public.daily_qa_effective_target().';
  end if;
  if to_regprocedure('public.daily_qa_get_or_start_set()') is null then
    raise exception 'Missing RPC public.daily_qa_get_or_start_set().';
  end if;
  if to_regprocedure('public.daily_qa_complete_item(uuid,text)') is null then
    raise exception 'Missing RPC public.daily_qa_complete_item(uuid,text).';
  end if;

  raise notice 'Q-A checks passed: P4 %, P5 %, P6 %, P7 % active Science questions (% total); shared profiles/admin allowlist found; smartple_profiles RLS is scoped; anon profile access is blocked; RLS/policies found for all seven Q-A data tables.', v_p4, v_p5, v_p6, v_p7, v_total;
end;
$$;
