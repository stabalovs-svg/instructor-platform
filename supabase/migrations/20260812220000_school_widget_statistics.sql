create or replace function public.get_my_school_widget_statistics(
  p_school_slug text,
  p_days integer default 30
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with requested_school as (
    select s.id, s.name, s.slug
    from public.driving_schools s
    join public.school_members m
      on m.school_id = s.id
      and m.user_id = auth.uid()
    where s.slug = p_school_slug
      and s.status = 'active'
    limit 1
  ),
  period as (
    select least(greatest(p_days, 1), 366) as days
  ),
  events as (
    select e.*
    from public.widget_events e
    join requested_school s on s.id = e.school_id
    cross join period p
    where e.occurred_at >= now() - make_interval(days => p.days)
      and e.source = 'school_widget'
  ),
  linked_instructors as (
    select p.id, concat_ws(' ', p.first_name, p.last_name) as name
    from requested_school s
    join public.school_instructor_links l
      on l.school_id = s.id
      and l.status = 'active'
      and l.show_in_widget = true
    join public.instructor_profiles p
      on p.id = l.instructor_id
      and p.status = 'active'
  ),
  instructor_totals as (
    select
      i.id,
      i.name,
      count(e.id) filter (where e.event_type = 'instructor_profile_view') as profile_views,
      count(e.id) filter (where e.event_type = 'phone_click') as phone_clicks
    from linked_instructors i
    left join events e on e.instructor_id = i.id
    group by i.id, i.name
  )
  select case
    when not exists (select 1 from requested_school) then null
    else jsonb_build_object(
      'school', (select jsonb_build_object('id', id, 'name', name, 'slug', slug) from requested_school),
      'periodDays', (select days from period),
      'widgetViews', (select count(*) from events where event_type = 'widget_view'),
      'profileViews', (select count(*) from events where event_type = 'instructor_profile_view'),
      'phoneClicks', (select count(*) from events where event_type = 'phone_click'),
      'filterUses', (select count(*) from events where event_type = 'filter_used'),
      'activeSeconds', (select coalesce(sum(active_seconds), 0) from events where event_type = 'session_end'),
      'uniqueSessions', (select count(distinct anonymous_session_id) from events),
      'instructors', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id,
          'name', name,
          'profileViews', profile_views,
          'phoneClicks', phone_clicks
        ) order by phone_clicks desc, profile_views desc, name)
        from instructor_totals
      ), '[]'::jsonb)
    )
  end;
$$;

revoke all on function public.get_my_school_widget_statistics(text, integer) from public;
grant execute on function public.get_my_school_widget_statistics(text, integer) to authenticated;

comment on function public.get_my_school_widget_statistics(text, integer) is
  'Returns aggregate widget engagement only to an authenticated member of the requested school.';
