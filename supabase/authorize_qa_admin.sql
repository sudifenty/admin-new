-- Run only in the EXISTING SmartPle Supabase project, after setup_shared_project.sql succeeds.
-- Run in Supabase SQL Editor as project owner; no email, password, or new Auth user is needed.
-- This authorizes only when exactly one existing SmartPle admin profile is linked to Auth.
-- If zero or multiple candidates exist, it stops without authorizing anyone.

do $$
declare
  v_admin_id uuid;
  v_admin_count integer;
begin
  select count(distinct q.user_id)
    into v_admin_count
  from public.daily_qa_profiles q
  join public.smartple_profiles p on p.user_id = q.user_id
  join auth.users u on u.id = q.user_id
  where q.role = 'admin'
    and p.role = 'admin';

  if v_admin_count <> 1 then
    raise exception 'Expected exactly one Auth-linked SmartPle administrator; found %. No Q-A admin was authorized.', v_admin_count;
  end if;

  select q.user_id
    into v_admin_id
  from public.daily_qa_profiles q
  join public.smartple_profiles p on p.user_id = q.user_id
  join auth.users u on u.id = q.user_id
  where q.role = 'admin'
    and p.role = 'admin'
  limit 1;

  insert into public.daily_qa_admins (user_id)
  values (v_admin_id)
  on conflict (user_id) do nothing;

  raise notice 'The single existing SmartPle administrator is authorized for Q-A.';
end;
$$;
