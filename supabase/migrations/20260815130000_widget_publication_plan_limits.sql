-- Public widget entitlement: non-Pro instructors can be published by one school,
-- while Pro instructors can be published by multiple schools.

create or replace function public.get_my_school_instructor_management(p_school_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with school as (
    select s.id, s.name, s.slug, s.widget_settings, m.role
    from public.driving_schools s
    join public.school_members m on m.school_id = s.id and m.user_id = auth.uid()
    where s.slug = p_school_slug and s.status = 'active'
    limit 1
  ),
  links as (
    select l.id, l.status, l.show_in_widget, l.started_at, l.ended_at,
      p.id as instructor_id, concat_ws(' ', p.first_name, p.last_name) as name,
      p.email, p.phone, p.is_public, p.status as profile_status,
      coalesce(sub.plan, p.plan) as plan,
      (select count(*) from public.school_instructor_links published
       where published.instructor_id = p.id
         and published.status = 'active'
         and published.show_in_widget = true) as visible_widget_count
    from school s
    join public.school_instructor_links l on l.school_id = s.id
    join public.instructor_profiles p on p.id = l.instructor_id
    left join public.instructor_subscriptions sub on sub.instructor_id = p.id
    order by case l.status when 'active' then 1 when 'invited' then 2 when 'paused' then 3 else 4 end,
      p.last_name, p.first_name
  )
  select case when not exists (select 1 from school) then null else jsonb_build_object(
    'school', (select jsonb_build_object('id', id, 'name', name, 'slug', slug, 'role', role, 'settings', widget_settings) from school),
    'instructors', coalesce((select jsonb_agg(jsonb_build_object(
      'linkId', id, 'instructorId', instructor_id, 'name', name, 'email', email,
      'phone', phone, 'status', status, 'showInWidget', show_in_widget,
      'isPublic', is_public, 'profileStatus', profile_status, 'plan', plan,
      'visibleWidgetCount', visible_widget_count,
      'startedAt', started_at, 'endedAt', ended_at
    )) from links), '[]'::jsonb)
  ) end;
$$;

create or replace function public.manage_school_instructor(
  p_school_slug text,
  p_link_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.school_instructor_links%rowtype;
  v_plan public.instructor_plan;
  v_other_widget_count integer;
begin
  select l.* into v_link
  from public.school_instructor_links l
  join public.driving_schools s on s.id = l.school_id
  where l.id = p_link_id
    and s.slug = p_school_slug
    and public.is_school_admin(s.id);

  if v_link.id is null then raise exception 'School link was not found'; end if;

  if p_action = 'show' then
    if v_link.status <> 'active' then raise exception 'Only an active instructor can be shown'; end if;

    select coalesce(sub.plan, p.plan) into v_plan
    from public.instructor_profiles p
    left join public.instructor_subscriptions sub on sub.instructor_id = p.id
    where p.id = v_link.instructor_id;

    select count(*) into v_other_widget_count
    from public.school_instructor_links other_link
    where other_link.instructor_id = v_link.instructor_id
      and other_link.id <> v_link.id
      and other_link.status = 'active'
      and other_link.show_in_widget = true;

    if v_plan <> 'pro' and v_other_widget_count >= 1 then
      raise exception 'WIDGET_SCHOOL_LIMIT_BASIC';
    end if;

    update public.school_instructor_links set show_in_widget = true where id = v_link.id returning * into v_link;
  elsif p_action = 'hide' then
    update public.school_instructor_links set show_in_widget = false where id = v_link.id returning * into v_link;
  elsif p_action = 'pause' then
    update public.school_instructor_links set status = 'paused', show_in_widget = false where id = v_link.id returning * into v_link;
  elsif p_action = 'resume' then
    update public.school_instructor_links set status = 'active', show_in_widget = false, started_at = coalesce(started_at, current_date), ended_at = null where id = v_link.id returning * into v_link;
  elsif p_action = 'end' then
    update public.school_instructor_links set status = 'ended', show_in_widget = false, ended_at = current_date where id = v_link.id returning * into v_link;
  else
    raise exception 'Unsupported action';
  end if;

  return jsonb_build_object('linkId', v_link.id, 'status', v_link.status, 'showInWidget', v_link.show_in_widget);
end;
$$;

create or replace function public.get_platform_admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_result jsonb;
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator access is required'; end if;
  select jsonb_build_object(
    'schools', coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'phone', s.phone, 'email', s.email, 'status', s.status,
      'widget', coalesce(s.widget_settings->>'layout', 'compact'),
      'instructors', (select count(*) from public.school_instructor_links l where l.school_id = s.id and l.status <> 'ended')
    ) order by s.name) from public.driving_schools s), '[]'::jsonb),
    'instructors', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', concat_ws(' ', p.first_name, p.last_name), 'phone', p.phone, 'email', p.email,
      'schools', coalesce((select jsonb_agg(s.name order by s.name) from public.school_instructor_links l
        join public.driving_schools s on s.id = l.school_id where l.instructor_id = p.id and l.status <> 'ended'), '[]'::jsonb),
      'widgetSchoolCount', (select count(*) from public.school_instructor_links l
        where l.instructor_id = p.id and l.status = 'active' and l.show_in_widget = true),
      'subscriptionId', sub.id, 'plan', coalesce(sub.plan, p.plan), 'status', coalesce(sub.status, 'trial'),
      'paidAt', sub.paid_at, 'periodMonths', sub.period_months, 'paidAmount', sub.paid_amount,
      'paidThrough', sub.valid_until, 'graceUntil', sub.grace_until,
      'terminationNoticeAt', sub.cancellation_notice_at,
      'terminationEffectiveOn', sub.cancellation_effective_on,
      'exportAccessUntil', sub.export_access_until, 'adminNote', sub.admin_note
    ) order by p.last_name, p.first_name) from public.instructor_profiles p
      left join public.instructor_subscriptions sub on sub.instructor_id = p.id), '[]'::jsonb),
    'paymentClaims', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'instructorId', c.instructor_id, 'instructor', concat_ws(' ', p.first_name, p.last_name),
      'createdAt', c.claimed_at, 'status', c.status, 'note', c.instructor_note,
      'resolvedAt', c.reviewed_at, 'reviewNote', c.review_note) order by c.claimed_at desc)
      from public.subscription_payment_claims c join public.instructor_profiles p on p.id = c.instructor_id), '[]'::jsonb),
    'auditLog', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'time', a.created_at, 'instructor', concat_ws(' ', p.first_name, p.last_name),
      'change', a.action, 'note', a.reason) order by a.created_at desc)
      from (select * from public.platform_admin_audit_log order by created_at desc limit 100) a
      left join public.instructor_profiles p on p.id = a.instructor_id), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.manage_school_instructor(text, uuid, text) from public;
grant execute on function public.manage_school_instructor(text, uuid, text) to authenticated;

comment on function public.manage_school_instructor(text, uuid, text) is
  'Allows school management while limiting non-Pro instructors to one public school widget.';
