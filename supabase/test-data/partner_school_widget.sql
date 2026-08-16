-- TEST PROJECT ONLY: IKARS Instructor Test.
-- Run manually in Supabase SQL Editor. This file is not a migration.

with school as (
  insert into public.driving_schools (name, slug, status, widget_settings)
  values (
    'Partneru autoskola',
    'partneru-autoskola',
    'active',
    jsonb_build_object('languages', jsonb_build_array('lv', 'ru'))
  )
  on conflict (slug) where slug is not null
  do update set name = excluded.name, status = excluded.status,
    widget_settings = excluded.widget_settings
  returning id
), target_school as (
  select id from school
  union all
  select id from public.driving_schools
  where slug = 'partneru-autoskola'
  limit 1
)
insert into public.school_instructor_links (
  school_id, instructor_id, status, show_in_widget, started_at
)
select s.id, p.id, 'active', true, current_date
from target_school s
cross join public.instructor_profiles p
where p.is_public = true and p.status = 'active'
on conflict (school_id, instructor_id)
do update set status = 'active', show_in_widget = true, ended_at = null;

select s.name, s.slug, count(l.id) as linked_public_instructors
from public.driving_schools s
left join public.school_instructor_links l
  on l.school_id = s.id and l.status = 'active' and l.show_in_widget = true
where s.slug = 'partneru-autoskola'
group by s.id, s.name, s.slug;
