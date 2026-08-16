alter table public.driving_schools
  add column if not exists slug text;

create unique index if not exists driving_schools_slug_key
  on public.driving_schools (slug)
  where slug is not null;

alter table public.driving_schools
  drop constraint if exists driving_schools_slug_format;

alter table public.driving_schools
  add constraint driving_schools_slug_format
  check (slug is null or slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');

create or replace function public.get_school_instructor_widget(
  p_school_slug text,
  p_start_date date default current_date,
  p_days integer default 14
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with school as (
    select s.id, s.name, s.logo_url, s.widget_settings
    from public.driving_schools s
    where s.slug = p_school_slug and s.status = 'active'
    limit 1
  ),
  directory as (
    select value as instructor
    from jsonb_array_elements(public.get_public_instructor_directory(p_start_date, p_days))
  ),
  linked as (
    select d.instructor
    from directory d
    join school s on true
    join public.school_instructor_links l
      on l.school_id = s.id
      and l.instructor_id = (d.instructor->>'id')::uuid
      and l.status = 'active'
      and l.show_in_widget = true
  )
  select case when not exists (select 1 from school) then null else jsonb_build_object(
    'school', (select jsonb_build_object(
      'name', s.name,
      'logoUrl', s.logo_url,
      'settings', s.widget_settings
    ) from school s),
    'instructors', coalesce((select jsonb_agg(l.instructor) from linked l), '[]'::jsonb)
  ) end;
$$;

revoke all on function public.get_school_instructor_widget(text, date, integer) from public;
grant execute on function public.get_school_instructor_widget(text, date, integer) to anon, authenticated;

comment on function public.get_school_instructor_widget(text, date, integer) is
  'Returns public data only for active instructors explicitly enabled in one school widget.';
