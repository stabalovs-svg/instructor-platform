-- IKARS Pro: revocable personal schedule links for students.
-- Only a hash of the secret token is stored in the database.

create extension if not exists pgcrypto;

create table if not exists public.student_schedule_links (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null unique references public.students(id) on delete cascade,
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  token_hash bytea not null unique,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  check ((enabled and revoked_at is null) or (not enabled))
);

alter table public.student_schedule_links enable row level security;

create index if not exists student_schedule_links_instructor_idx
  on public.student_schedule_links (instructor_id, student_id);

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
  if v_plan <> 'pro' then raise exception 'STUDENT_SCHEDULE_REQUIRES_PRO'; end if;
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

create or replace function public.revoke_student_schedule_link(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_instructor_id uuid;
begin
  select id into v_instructor_id
  from public.instructor_profiles where user_id = auth.uid();

  update public.student_schedule_links
  set enabled = false, revoked_at = now()
  where student_id = p_student_id and instructor_id = v_instructor_id;
end;
$$;

create or replace function public.get_student_personal_schedule(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_link public.student_schedule_links;
  v_student public.students;
  v_instructor public.instructor_profiles;
begin
  if p_token is null or length(p_token) <> 64 then return null; end if;

  select * into v_link
  from public.student_schedule_links
  where token_hash = digest(p_token, 'sha256')
    and enabled = true and revoked_at is null;

  if v_link.id is null then return null; end if;

  select * into v_student from public.students where id = v_link.student_id;
  select * into v_instructor from public.instructor_profiles where id = v_link.instructor_id;

  return jsonb_build_object(
    'brand', 'IKARS',
    'student', jsonb_build_object(
      'firstName', v_student.first_name,
      'lastName', v_student.last_name
    ),
    'instructor', jsonb_build_object(
      'firstName', v_instructor.first_name,
      'lastName', v_instructor.last_name,
      'phone', v_instructor.phone
    ),
    'statistics', jsonb_build_object(
      'completedLessons', (
        select count(*) from public.lessons l
        where l.student_id = v_student.id and l.instructor_id = v_instructor.id
          and l.status in ('completed', 'no_show') and l.starts_at <= now()
      ),
      'paidAmount', coalesce((
        select sum(p.amount) from public.payments p
        where p.student_id = v_student.id and p.instructor_id = v_instructor.id
          and p.voided_at is null
      ), 0)
    ),
    'lessons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id,
        'startsAt', l.starts_at,
        'endsAt', l.ends_at,
        'serviceType', l.service_type,
        'status', l.status,
        'price', l.price,
        'paid', exists (
          select 1 from public.payments payment
          where payment.lesson_id = l.id and payment.voided_at is null
        ),
        'vehicle', case when v.id is null then null else jsonb_build_object(
          'model', v.model, 'transmission', v.transmission
        ) end,
        'meetingPoint', case when mp.id is null then null else jsonb_build_object(
          'name', mp.public_name, 'district', mp.district
        ) end
      ) order by l.starts_at)
      from public.lessons l
      left join public.vehicles v on v.id = l.vehicle_id
      left join public.meeting_points mp on mp.id = l.meeting_point_id
      where l.student_id = v_student.id and l.instructor_id = v_instructor.id
        and l.status <> 'cancelled'
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on table public.student_schedule_links from anon, authenticated;
revoke all on function public.create_student_schedule_link(uuid) from public;
revoke all on function public.revoke_student_schedule_link(uuid) from public;
revoke all on function public.get_student_personal_schedule(text) from public;
grant execute on function public.create_student_schedule_link(uuid) to authenticated;
grant execute on function public.revoke_student_schedule_link(uuid) to authenticated;
grant execute on function public.get_student_personal_schedule(text) to anon, authenticated;

comment on table public.student_schedule_links is
  'Revocable IKARS Pro links for a student to view only their own schedule.';
