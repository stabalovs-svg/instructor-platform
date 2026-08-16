-- School administrator controls for widget layout, theme and instructor photos.

create or replace function public.get_my_school_instructor_management(p_school_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with school as (
    select s.id, s.name, s.slug, s.widget_settings, m.role
    from public.driving_schools s
    join public.school_members m on m.school_id = s.id and m.user_id = auth.uid()
    where s.slug = p_school_slug and s.status = 'active'
    limit 1
  ),
  links as (
    select l.id, l.status, l.show_in_widget, l.started_at, l.ended_at,
      p.id as instructor_id, concat_ws(' ', p.first_name, p.last_name) as name,
      p.email, p.phone, p.is_public, p.status as profile_status
    from school s
    join public.school_instructor_links l on l.school_id = s.id
    join public.instructor_profiles p on p.id = l.instructor_id
    order by case l.status when 'active' then 1 when 'invited' then 2 when 'paused' then 3 else 4 end,
      p.last_name, p.first_name
  )
  select case when not exists (select 1 from school) then null else jsonb_build_object(
    'school', (select jsonb_build_object('id', id, 'name', name, 'slug', slug, 'role', role, 'settings', widget_settings) from school),
    'instructors', coalesce((select jsonb_agg(jsonb_build_object(
      'linkId', id, 'instructorId', instructor_id, 'name', name, 'email', email,
      'phone', phone, 'status', status, 'showInWidget', show_in_widget,
      'isPublic', is_public, 'profileStatus', profile_status,
      'startedAt', started_at, 'endedAt', ended_at
    )) from links), '[]'::jsonb)
  ) end;
$$;

create or replace function public.update_my_school_widget_settings(
  p_school_slug text,
  p_settings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_school_id uuid;
  v_layout text := coalesce(p_settings->>'layout', 'compact');
  v_theme text := coalesce(p_settings->>'theme', 'ikars');
  v_accent text := coalesce(p_settings->>'accentColor', '#0d827b');
  v_show_photos boolean := coalesce((p_settings->>'showPhotos')::boolean, true);
  v_settings jsonb;
begin
  select s.id into v_school_id
  from public.driving_schools s
  where s.slug = p_school_slug and s.status = 'active' and public.is_school_admin(s.id);

  if v_school_id is null then raise exception 'School administrator access is required'; end if;
  if v_layout not in ('banner', 'compact', 'full') then raise exception 'Unsupported widget layout'; end if;
  if v_theme not in ('ikars', 'baltic', 'sand', 'graphite', 'custom') then raise exception 'Unsupported widget theme'; end if;
  if v_accent !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid accent color'; end if;

  v_settings := jsonb_build_object(
    'layout', v_layout,
    'theme', v_theme,
    'accentColor', lower(v_accent),
    'showPhotos', v_show_photos
  );

  update public.driving_schools set widget_settings = v_settings where id = v_school_id;
  return v_settings;
end;
$$;

revoke all on function public.update_my_school_widget_settings(text, jsonb) from public;
grant execute on function public.update_my_school_widget_settings(text, jsonb) to authenticated;

