-- Tighten access to the EXISTING SmartPle profile table without deleting or
-- changing profile rows. Run as project owner in the existing Supabase project.
--
-- Target access model:
--   * anon/PUBLIC: no direct table access
--   * authenticated student: SELECT their own profile only
--   * authenticated SmartPle admin: SELECT/UPDATE profiles for admin controls
--   * direct student INSERT/UPDATE/DELETE: not allowed
--
-- Existing signup/admin RPCs that create profiles must remain SECURITY DEFINER.
-- This script stops before changes if it finds unexpected profile policies.

begin;

do $$
declare
  v_unexpected_policies text;
begin
  if to_regclass('public.smartple_profiles') is null then
    raise exception 'Missing public.smartple_profiles; stopped before changes.';
  end if;
  if not exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='smartple_profiles' and column_name='user_id'
     )
     or not exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='smartple_profiles' and column_name='role'
     ) then
    raise exception 'smartple_profiles must have user_id and role columns; stopped before changes.';
  end if;

  select string_agg(policyname, ', ' order by policyname)
    into v_unexpected_policies
  from pg_catalog.pg_policies
  where schemaname = 'public'
    and tablename = 'smartple_profiles'
    and policyname not in (
      'allow all',
      'allow all profiles',
      'smartple_profiles_self_select',
      'smartple_profiles_admin_update'
    );

  if v_unexpected_policies is not null then
    raise exception 'Unexpected smartple_profiles policy/policies found (%). No changes made; review them first.', v_unexpected_policies;
  end if;
end;
$$;

-- SECURITY DEFINER avoids policy recursion when checking the admin's own role.
-- It returns only whether the current Auth user has role=admin.
create or replace function public.smartple_profiles_admin_for_rls()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.smartple_profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'admin'
  );
$$;
revoke all on function public.smartple_profiles_admin_for_rls() from public, anon, authenticated;
grant execute on function public.smartple_profiles_admin_for_rls() to authenticated;

-- Remove any column-level grants as well as table-level grants for browser roles.
do $$
declare
  v_column record;
begin
  for v_column in
    select column_name
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'smartple_profiles'
  loop
    execute format(
      'revoke all privileges (%I) on table public.smartple_profiles from public, anon, authenticated',
      v_column.column_name
    );
  end loop;
end;
$$;
revoke all privileges on table public.smartple_profiles from public, anon, authenticated;

-- Replace the two reported allow-all policies with least-privilege policies.
drop policy if exists "allow all" on public.smartple_profiles;
drop policy if exists "allow all profiles" on public.smartple_profiles;
drop policy if exists smartple_profiles_self_select on public.smartple_profiles;
drop policy if exists smartple_profiles_admin_update on public.smartple_profiles;

create policy smartple_profiles_self_select
on public.smartple_profiles
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.smartple_profiles_admin_for_rls()
);

create policy smartple_profiles_admin_update
on public.smartple_profiles
for update to authenticated
using (public.smartple_profiles_admin_for_rls())
with check (public.smartple_profiles_admin_for_rls());

-- Keep row data unchanged; RLS now governs direct API requests.
alter table public.smartple_profiles enable row level security;
grant select, update on table public.smartple_profiles to authenticated;

commit;
