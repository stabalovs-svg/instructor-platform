create or replace function public.get_my_school_invitations()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with owner as (
    select id from public.instructor_profiles where user_id = auth.uid()
  ),
  invitations as (
    select l.id, s.id as school_id, s.name, s.slug, l.created_at
    from owner o
    join public.school_instructor_links l on l.instructor_id = o.id and l.status = 'invited'
    join public.driving_schools s on s.id = l.school_id and s.status = 'active'
    order by l.created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'linkId', id,
    'schoolId', school_id,
    'schoolName', name,
    'schoolSlug', slug,
    'invitedAt', created_at
  )), '[]'::jsonb)
  from invitations;
$$;

create or replace function public.respond_to_school_invitation(
  p_link_id uuid,
  p_response text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.school_instructor_links%rowtype;
begin
  select l.* into v_link
  from public.school_instructor_links l
  join public.instructor_profiles p on p.id = l.instructor_id
  where l.id = p_link_id
    and p.user_id = auth.uid()
    and l.status = 'invited';

  if v_link.id is null then raise exception 'Invitation was not found'; end if;

  if p_response = 'accept' then
    update public.school_instructor_links
    set status = 'active', show_in_widget = false, started_at = current_date, ended_at = null
    where id = v_link.id
    returning * into v_link;
  elsif p_response = 'decline' then
    update public.school_instructor_links
    set status = 'ended', show_in_widget = false, ended_at = current_date
    where id = v_link.id
    returning * into v_link;
  else
    raise exception 'Unsupported response';
  end if;

  return jsonb_build_object('linkId', v_link.id, 'status', v_link.status, 'showInWidget', v_link.show_in_widget);
end;
$$;

revoke all on function public.get_my_school_invitations() from public;
revoke all on function public.respond_to_school_invitation(uuid, text) from public;
grant execute on function public.get_my_school_invitations() to authenticated;
grant execute on function public.respond_to_school_invitation(uuid, text) to authenticated;

comment on function public.get_my_school_invitations() is
  'Returns only pending school invitations belonging to the signed-in instructor.';
comment on function public.respond_to_school_invitation(uuid, text) is
  'Lets an instructor accept or decline only their own pending invitation; acceptance remains hidden from the widget.';
