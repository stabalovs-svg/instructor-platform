-- Instructor-controlled disclosure for each personal student schedule.

alter table public.student_schedule_links
  add column if not exists show_full_history boolean not null default true;

create or replace function public.get_student_schedule_settings(p_student_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'enabled', coalesce(l.enabled and l.revoked_at is null, false),
    'showFullHistory', coalesce(l.show_full_history, true)
  )
  from public.students s
  join public.instructor_profiles p on p.id = s.instructor_id and p.user_id = auth.uid()
  left join public.student_schedule_links l on l.student_id = s.id
  where s.id = p_student_id;
$$;

create or replace function public.set_student_schedule_visibility(
  p_student_id uuid,
  p_show_full_history boolean
)
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
  set show_full_history = p_show_full_history
  where student_id = p_student_id and instructor_id = v_instructor_id;

  if not found then raise exception 'Student schedule link not found'; end if;
end;
$$;

create or replace function public.get_student_personal_schedule_v2(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_data jsonb;
  v_full boolean;
  v_lessons jsonb;
begin
  select l.show_full_history into v_full
  from public.student_schedule_links l
  where l.token_hash = digest(p_token, 'sha256')
    and l.enabled = true and l.revoked_at is null;

  if v_full is null then return null; end if;
  v_data := public.get_student_personal_schedule(p_token);
  if v_data is null then return null; end if;

  if v_full then
    return jsonb_set(v_data, '{settings}', jsonb_build_object('showFullHistory', true));
  end if;

  select coalesce(jsonb_agg(item order by (item->>'startsAt')::timestamptz), '[]'::jsonb)
    into v_lessons
  from jsonb_array_elements(coalesce(v_data->'lessons', '[]'::jsonb)) item
  where (item->>'startsAt')::timestamptz >= now()
     or coalesce((item->>'paid')::boolean, false) = false;

  v_data := jsonb_set(v_data, '{lessons}', v_lessons);
  v_data := jsonb_set(v_data, '{statistics}', '{}'::jsonb);
  return jsonb_set(v_data, '{settings}', jsonb_build_object('showFullHistory', false));
end;
$$;

create or replace function public.get_student_personal_finance_v2(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_data jsonb;
  v_full boolean;
begin
  select l.show_full_history into v_full
  from public.student_schedule_links l
  where l.token_hash = digest(p_token, 'sha256')
    and l.enabled = true and l.revoked_at is null;

  if v_full is null then return null; end if;
  v_data := public.get_student_personal_finance(p_token);
  if v_data is null then return null; end if;

  if v_full then
    return v_data || jsonb_build_object('showFullHistory', true);
  end if;

  return jsonb_build_object(
    'showFullHistory', false,
    'debtAmount', coalesce(v_data->'debtAmount', '0'::jsonb),
    'creditAmount', coalesce(v_data->'creditAmount', '0'::jsonb)
  );
end;
$$;

revoke all on function public.get_student_schedule_settings(uuid) from public;
revoke all on function public.set_student_schedule_visibility(uuid, boolean) from public;
revoke all on function public.get_student_personal_schedule_v2(text) from public;
revoke all on function public.get_student_personal_finance_v2(text) from public;
grant execute on function public.get_student_schedule_settings(uuid) to authenticated;
grant execute on function public.set_student_schedule_visibility(uuid, boolean) to authenticated;
grant execute on function public.get_student_personal_schedule_v2(text) to anon, authenticated;
grant execute on function public.get_student_personal_finance_v2(text) to anon, authenticated;

revoke execute on function public.get_student_personal_schedule(text) from anon, authenticated;
revoke execute on function public.get_student_personal_finance(text) from anon, authenticated;

comment on column public.student_schedule_links.show_full_history is
  'When false, the student receives future lessons, unpaid past lessons and balance only.';
