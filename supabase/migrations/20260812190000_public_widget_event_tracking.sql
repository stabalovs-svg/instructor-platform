create or replace function public.record_public_widget_event(
  p_event_type text,
  p_session_id uuid,
  p_source text default 'catalog',
  p_school_slug text default null,
  p_instructor_id uuid default null,
  p_active_seconds integer default null,
  p_language text default 'lv',
  p_device_type text default 'desktop',
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_school_id uuid;
  v_event_type public.widget_event_type;
begin
  if p_event_type not in ('widget_view', 'instructor_profile_view', 'phone_click', 'filter_used', 'session_end') then
    raise exception 'Unsupported event type';
  end if;
  if p_source not in ('catalog', 'school_widget') then raise exception 'Unsupported source'; end if;
  if p_language not in ('lv', 'ru') then raise exception 'Unsupported language'; end if;
  if p_device_type not in ('mobile', 'tablet', 'desktop') then raise exception 'Unsupported device'; end if;
  if p_active_seconds is not null and (p_active_seconds < 0 or p_active_seconds > 86400) then
    raise exception 'Invalid active time';
  end if;
  if pg_column_size(coalesce(p_metadata, '{}'::jsonb)) > 2048 then raise exception 'Metadata too large'; end if;

  if p_source = 'school_widget' then
    select id into v_school_id from public.driving_schools
    where slug = p_school_slug and status = 'active';
    if v_school_id is null then raise exception 'School widget not found'; end if;
  end if;

  if p_instructor_id is not null and not exists (
    select 1 from public.instructor_profiles p
    where p.id = p_instructor_id and p.is_public = true and p.status = 'active'
  ) then raise exception 'Instructor is not public'; end if;

  if p_source = 'school_widget' and p_instructor_id is not null and not exists (
    select 1 from public.school_instructor_links l
    where l.school_id = v_school_id and l.instructor_id = p_instructor_id
      and l.status = 'active' and l.show_in_widget = true
  ) then raise exception 'Instructor is not available in this widget'; end if;

  v_event_type := p_event_type::public.widget_event_type;

  if p_event_type <> 'phone_click' and exists (
    select 1 from public.widget_events e
    where e.anonymous_session_id = p_session_id
      and e.event_type = v_event_type
      and e.source = p_source
      and e.school_id is not distinct from v_school_id
      and e.instructor_id is not distinct from p_instructor_id
      and e.occurred_at > now() - interval '30 seconds'
  ) then return; end if;

  insert into public.widget_events (
    event_type, source, school_id, instructor_id, anonymous_session_id,
    active_seconds, language, device_type, metadata
  ) values (
    v_event_type, p_source, v_school_id, p_instructor_id, p_session_id,
    p_active_seconds, p_language, p_device_type, coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.record_public_widget_event(text, uuid, text, text, uuid, integer, text, text, jsonb) from public;
grant execute on function public.record_public_widget_event(text, uuid, text, text, uuid, integer, text, text, jsonb) to anon, authenticated;

comment on function public.record_public_widget_event(text, uuid, text, text, uuid, integer, text, text, jsonb) is
  'Accepts validated anonymous catalog/widget analytics without delaying navigation or exposing private CRM data.';
