create or replace function public.get_my_public_statistics(p_days integer default 30)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with owner as (
    select id from public.instructor_profiles where user_id = auth.uid()
  ),
  events as (
    select e.* from public.widget_events e
    join owner o on o.id = e.instructor_id
    where e.occurred_at >= now() - make_interval(days => least(greatest(p_days, 1), 366))
  )
  select jsonb_build_object(
    'profileViews', count(*) filter (where event_type = 'instructor_profile_view'),
    'phoneClicks', count(*) filter (where event_type = 'phone_click'),
    'catalogPhoneClicks', count(*) filter (where event_type = 'phone_click' and source = 'catalog'),
    'widgetPhoneClicks', count(*) filter (where event_type = 'phone_click' and source = 'school_widget'),
    'periodDays', least(greatest(p_days, 1), 366)
  ) from events;
$$;

revoke all on function public.get_my_public_statistics(integer) from public;
grant execute on function public.get_my_public_statistics(integer) to authenticated;

comment on function public.get_my_public_statistics(integer) is
  'Returns aggregate public profile and attempted-call statistics only to the owning instructor.';
