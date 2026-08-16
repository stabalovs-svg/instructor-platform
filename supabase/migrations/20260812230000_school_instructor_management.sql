create or replace function public.get_my_school_instructor_management(p_school_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with school as (
    select s.id, s.name, s.slug, m.role
    from public.driving_schools s
    join public.school_members m on m.school_id = s.id and m.user_id = auth.uid()
    where s.slug = p_school_slug and s.status = 'active'
    limit 1
  ),
  links as (
    select
      l.id,
      l.status,
      l.show_in_widget,
      l.started_at,
      l.ended_at,
      p.id as instructor_id,
      concat_ws(' ', p.first_name, p.last_name) as name,
      p.email,
      p.phone,
      p.is_public,
      p.status as profile_status
    from school s
    join public.school_instructor_links l on l.school_id = s.id
    join public.instructor_profiles p on p.id = l.instructor_id
    order by
      case l.status when 'active' then 1 when 'invited' then 2 when 'paused' then 3 else 4 end,
      p.last_name,
      p.first_name
  )
  select case when not exists (select 1 from school) then null else jsonb_build_object(
    'school', (select jsonb_build_object('id', id, 'name', name, 'slug', slug, 'role', role) from school),
    'instructors', coalesce((select jsonb_agg(jsonb_build_object(
      'linkId', id,
      'instructorId', instructor_id,
      'name', name,
      'email', email,
      'phone', phone,
      'status', status,
      'showInWidget', show_in_widget,
      'isPublic', is_public,
      'profileStatus', profile_status,
      'startedAt', started_at,
      'endedAt', ended_at
    )) from links), '[]'::jsonb)
  ) end;
$$;

create or replace function public.invite_school_instructor(
  p_school_slug text,
  p_instructor_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_school_id uuid;
  v_instructor public.instructor_profiles%rowtype;
  v_link public.school_instructor_links%rowtype;
begin
  select s.id into v_school_id
  from public.driving_schools s
  where s.slug = p_school_slug
    and s.status = 'active'
    and public.is_school_admin(s.id);

  if v_school_id is null then raise exception 'School administrator access is required'; end if;
  if nullif(trim(p_instructor_email), '') is null then raise exception 'Instructor email is required'; end if;

  select p.* into v_instructor
  from public.instructor_profiles p
  where lower(p.email) = lower(trim(p_instructor_email))
    and p.status <> 'archived'
  limit 1;

  if v_instructor.id is null then raise exception 'Instructor profile was not found'; end if;

  insert into public.school_instructor_links (
    school_id, instructor_id, status, show_in_widget, started_at, ended_at
  ) values (
    v_school_id, v_instructor.id, 'invited', false, null, null
  )
  on conflict (school_id, instructor_id) do update set
    status = case when public.school_instructor_links.status = 'active' then 'active'::public.school_link_status else 'invited'::public.school_link_status end,
    show_in_widget = case when public.school_instructor_links.status = 'active' then public.school_instructor_links.show_in_widget else false end,
    ended_at = null,
    updated_at = now()
  returning * into v_link;

  return jsonb_build_object(
    'linkId', v_link.id,
    'name', concat_ws(' ', v_instructor.first_name, v_instructor.last_name),
    'status', v_link.status,
    'showInWidget', v_link.show_in_widget
  );
end;
$$;

create or replace function public.manage_school_instructor(
  p_school_slug text,
  p_link_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.school_instructor_links%rowtype;
begin
  select l.* into v_link
  from public.school_instructor_links l
  join public.driving_schools s on s.id = l.school_id
  where l.id = p_link_id
    and s.slug = p_school_slug
    and public.is_school_admin(s.id);

  if v_link.id is null then raise exception 'School link was not found'; end if;

  if p_action = 'show' then
    if v_link.status <> 'active' then raise exception 'Only an active instructor can be shown'; end if;
    update public.school_instructor_links set show_in_widget = true where id = v_link.id returning * into v_link;
  elsif p_action = 'hide' then
    update public.school_instructor_links set show_in_widget = false where id = v_link.id returning * into v_link;
  elsif p_action = 'pause' then
    update public.school_instructor_links set status = 'paused', show_in_widget = false where id = v_link.id returning * into v_link;
  elsif p_action = 'resume' then
    update public.school_instructor_links set status = 'active', show_in_widget = false, started_at = coalesce(started_at, current_date), ended_at = null where id = v_link.id returning * into v_link;
  elsif p_action = 'end' then
    update public.school_instructor_links set status = 'ended', show_in_widget = false, ended_at = current_date where id = v_link.id returning * into v_link;
  else
    raise exception 'Unsupported action';
  end if;

  return jsonb_build_object('linkId', v_link.id, 'status', v_link.status, 'showInWidget', v_link.show_in_widget);
end;
$$;

revoke all on function public.get_my_school_instructor_management(text) from public;
revoke all on function public.invite_school_instructor(text, text) from public;
revoke all on function public.manage_school_instructor(text, uuid, text) from public;
grant execute on function public.get_my_school_instructor_management(text) to authenticated;
grant execute on function public.invite_school_instructor(text, text) to authenticated;
grant execute on function public.manage_school_instructor(text, uuid, text) to authenticated;

comment on function public.get_my_school_instructor_management(text) is
  'Returns school-link and public contact fields only; it never returns students, lessons or payments.';
comment on function public.invite_school_instructor(text, text) is
  'Creates a non-public invitation for an existing instructor profile by exact email match.';
comment on function public.manage_school_instructor(text, uuid, text) is
  'Allows a school admin to show, hide, pause, resume or end only its own instructor link.';
