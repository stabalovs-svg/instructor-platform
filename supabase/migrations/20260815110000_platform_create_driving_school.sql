-- Allow a verified IKARS platform administrator to create a pilot school
-- and assign its first administrator in one audited operation.

create or replace function public.platform_create_driving_school(
  p_name text,
  p_slug text,
  p_admin_email text,
  p_registration_number text default null,
  p_email text default null,
  p_phone text default null,
  p_website_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school public.driving_schools%rowtype;
  v_admin_user_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator access is required';
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 then raise exception 'School name is required'; end if;
  if coalesce(p_slug, '') !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then raise exception 'Invalid school slug'; end if;
  if nullif(trim(coalesce(p_admin_email, '')), '') is null then raise exception 'School administrator email is required'; end if;

  select id into v_admin_user_id
  from auth.users
  where lower(email) = lower(trim(p_admin_email));
  if v_admin_user_id is null then
    raise exception 'The school administrator must register before the school is created';
  end if;

  insert into public.driving_schools (
    name, slug, registration_number, email, phone, website_url, status, widget_settings
  ) values (
    trim(p_name), p_slug, nullif(trim(p_registration_number), ''),
    nullif(trim(p_email), ''), nullif(trim(p_phone), ''), nullif(trim(p_website_url), ''),
    'active', jsonb_build_object('layout', 'compact', 'theme', 'ikars', 'showPhotos', true)
  ) returning * into v_school;

  insert into public.school_members (school_id, user_id, role)
  values (v_school.id, v_admin_user_id, 'admin');

  insert into public.platform_admin_audit_log (
    actor_user_id, entity_type, entity_id, action, after_data, reason
  ) values (
    auth.uid(), 'driving_school', v_school.id, 'school_created',
    jsonb_build_object('school', to_jsonb(v_school), 'administratorEmail', lower(trim(p_admin_email))),
    'Pilot school created from the platform administration cabinet'
  );

  return jsonb_build_object(
    'id', v_school.id, 'name', v_school.name, 'slug', v_school.slug,
    'administratorEmail', lower(trim(p_admin_email))
  );
exception
  when unique_violation then
    raise exception 'A school with this system address already exists';
end;
$$;

revoke all on function public.platform_create_driving_school(text, text, text, text, text, text, text) from public;
grant execute on function public.platform_create_driving_school(text, text, text, text, text, text, text) to authenticated;

comment on function public.platform_create_driving_school(text, text, text, text, text, text, text) is
  'Creates a school and its first administrator after platform-admin and existing-user checks.';
