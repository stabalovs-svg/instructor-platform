create or replace function public.get_public_instructor_directory(
  p_start_date date default current_date,
  p_days integer default 14
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with public_profiles as (
    select p.*, r.enabled_weekdays, r.first_lesson, r.last_lesson,
      r.slot_minutes, r.public_horizon_days
    from public.instructor_profiles p
    join public.availability_rules r on r.instructor_id = p.id
    where p.is_public = true and p.status = 'active'
  ),
  public_slots as (
    select p.id as instructor_id, d.day::date as slot_date,
      (p.first_lesson + make_interval(mins => n.value * p.slot_minutes))::time as slot_time,
      ((d.day::date + (p.first_lesson + make_interval(mins => n.value * p.slot_minutes))::time)
        at time zone p.timezone) as starts_at,
      ((d.day::date + (p.first_lesson + make_interval(mins => (n.value + 1) * p.slot_minutes))::time)
        at time zone p.timezone) as ends_at
    from public_profiles p
    cross join lateral generate_series(
      p_start_date,
      p_start_date + (least(greatest(p_days, 1), p.public_horizon_days) - 1),
      interval '1 day'
    ) d(day)
    cross join lateral generate_series(
      0,
      floor(extract(epoch from (p.last_lesson - p.first_lesson)) / 60 / p.slot_minutes)::integer
    ) n(value)
    where extract(dow from d.day)::smallint = any(p.enabled_weekdays)
  ),
  available_slots as (
    select s.*
    from public_slots s
    where not exists (
      select 1 from public.lessons l
      where l.instructor_id = s.instructor_id
        and l.status in ('planned', 'completed', 'no_show')
        and tstzrange(l.starts_at, l.ends_at, '[)') && tstzrange(s.starts_at, s.ends_at, '[)')
    )
    and not exists (
      select 1 from public.calendar_blocks b
      where b.instructor_id = s.instructor_id
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(s.starts_at, s.ends_at, '[)')
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', concat_ws(' ', p.first_name, p.last_name),
    'languages', p.languages,
    'categories', p.categories,
    'phone', case when p.public_phone then p.phone else null end,
    'description', p.description,
    'meetingPoints', coalesce((
      select jsonb_agg(concat_ws(' — ', m.district, m.public_name) order by m.sort_order, m.public_name)
      from public.meeting_points m
      where m.instructor_id = p.id and m.is_active = true
    ), '[]'::jsonb),
    'vehicles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id,
        'name', concat_ws(' ', v.make, v.model),
        'transmission', case when v.transmission = 'automatic' then 'A' else 'M' end,
        'price', v.lesson_price,
        'weekendPrice', v.weekend_price,
        'photoUrl', v.photo_url
      ) order by v.sort_order, v.make, v.model)
      from public.vehicles v
      where v.instructor_id = p.id and v.is_active = true
    ), '[]'::jsonb),
    'availability', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', to_char(a.slot_date, 'YYYY-MM-DD'),
        'time', to_char(a.slot_time, 'HH24:MI')
      ) order by a.slot_date, a.slot_time)
      from available_slots a
      where a.instructor_id = p.id
    ), '[]'::jsonb)
  ) order by p.last_name, p.first_name), '[]'::jsonb)
  from public_profiles p;
$$;

revoke all on function public.get_public_instructor_directory(date, integer) from public;
grant execute on function public.get_public_instructor_directory(date, integer) to anon, authenticated;

comment on function public.get_public_instructor_directory(date, integer) is
  'Returns only explicitly public instructor data and calculated free slots. Student, lesson, block and payment details are never exposed.';
