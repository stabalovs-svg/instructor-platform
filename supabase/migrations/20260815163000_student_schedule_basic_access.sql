-- Personal student schedules are part of Basic and Pro.
-- Push subscriptions will be guarded separately as a Pro feature.

create or replace function public.create_student_schedule_link(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_instructor_id uuid;
  v_plan public.instructor_plan;
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_link public.student_schedule_links;
begin
  select p.id, coalesce(s.plan, p.plan)
    into v_instructor_id, v_plan
  from public.instructor_profiles p
  left join public.instructor_subscriptions s on s.instructor_id = p.id
  where p.user_id = auth.uid();

  if v_instructor_id is null then raise exception 'Instructor profile not found'; end if;
  if v_plan not in ('basic', 'pro') then raise exception 'STUDENT_SCHEDULE_REQUIRES_BASIC'; end if;
  if not exists (
    select 1 from public.students st
    where st.id = p_student_id and st.instructor_id = v_instructor_id
  ) then raise exception 'Student not found'; end if;

  insert into public.student_schedule_links (
    student_id, instructor_id, token_hash, enabled, created_by
  ) values (
    p_student_id, v_instructor_id, digest(v_token, 'sha256'), true, auth.uid()
  )
  on conflict (student_id) do update set
    token_hash = excluded.token_hash,
    enabled = true,
    created_at = now(),
    created_by = auth.uid(),
    revoked_at = null
  returning * into v_link;

  return jsonb_build_object('token', v_token, 'createdAt', v_link.created_at);
end;
$$;

revoke all on function public.create_student_schedule_link(uuid) from public;
grant execute on function public.create_student_schedule_link(uuid) to authenticated;

comment on function public.create_student_schedule_link(uuid) is
  'Creates a revocable student schedule link for Basic and Pro instructors.';
