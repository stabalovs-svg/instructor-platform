-- Test data only. Gives the first instructor already linked to the partner school
-- access to that school's protected statistics dashboard.
insert into public.school_members (school_id, user_id, role)
select l.school_id, p.user_id, 'admin'
from public.school_instructor_links l
join public.driving_schools s on s.id = l.school_id
join public.instructor_profiles p on p.id = l.instructor_id
where s.slug = 'partneru-autoskola'
  and l.status = 'active'
  and p.user_id is not null
order by l.created_at
limit 1
on conflict (school_id, user_id) do update set role = excluded.role;

select s.name, s.slug, m.role
from public.school_members m
join public.driving_schools s on s.id = m.school_id
where s.slug = 'partneru-autoskola';
