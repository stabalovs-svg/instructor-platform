-- Create the tenant profile automatically when an instructor Auth user is added.
-- Apply only to the dedicated IKARS Instructor Test project.

create or replace function public.handle_new_instructor_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.instructor_profiles (user_id, first_name, last_name, email)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 'IKARS'),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), 'Instructor'),
    new.email
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_instructor_profile on auth.users;
create trigger on_auth_user_created_instructor_profile
  after insert on auth.users
  for each row execute function public.handle_new_instructor_user();
