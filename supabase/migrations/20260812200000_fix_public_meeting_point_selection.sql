create or replace function public.select_public_meeting_point(p_meeting_point_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_instructor_id uuid;
begin
  select m.instructor_id into v_instructor_id
  from public.meeting_points m
  join public.instructor_profiles p on p.id = m.instructor_id
  where m.id = p_meeting_point_id
    and m.is_active = true
    and p.user_id = auth.uid();

  if v_instructor_id is null then
    raise exception 'Meeting point not found';
  end if;

  update public.meeting_points
  set show_in_widget = false
  where instructor_id = v_instructor_id and show_in_widget = true;

  update public.meeting_points
  set show_in_widget = true
  where id = p_meeting_point_id and instructor_id = v_instructor_id;
end;
$$;

revoke all on function public.select_public_meeting_point(uuid) from public;
grant execute on function public.select_public_meeting_point(uuid) to authenticated;
