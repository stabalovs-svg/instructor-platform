-- Schedule or cancel an instructor subscription termination without losing billing history.

alter table public.instructor_subscriptions
  add column cancellation_effective_on date;

create or replace function public.manage_platform_subscription_termination(
  p_instructor_id uuid,
  p_effective_on date,
  p_export_access_until date,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.instructor_subscriptions%rowtype;
  v_after public.instructor_subscriptions%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator access is required';
  end if;

  select * into v_before
  from public.instructor_subscriptions
  where instructor_id = p_instructor_id
  for update;

  if v_before.id is null then raise exception 'Subscription was not found'; end if;
  if p_effective_on is not null and p_effective_on < current_date then
    raise exception 'Termination date cannot be in the past';
  end if;
  if p_export_access_until is not null and p_effective_on is null then
    raise exception 'Termination date is required for export access';
  end if;
  if p_export_access_until is not null and p_export_access_until < p_effective_on then
    raise exception 'Export access cannot end before termination';
  end if;

  update public.instructor_subscriptions
  set cancellation_notice_at = case when p_effective_on is null then null else now() end,
      cancellation_effective_on = p_effective_on,
      export_access_until = p_export_access_until,
      admin_note = coalesce(nullif(trim(p_note), ''), admin_note)
  where instructor_id = p_instructor_id
  returning * into v_after;

  insert into public.platform_admin_audit_log (
    actor_user_id, instructor_id, entity_type, entity_id, action,
    before_data, after_data, reason
  ) values (
    auth.uid(), p_instructor_id, 'instructor_subscription', v_after.id,
    case when p_effective_on is null then 'termination_cancelled' else 'termination_scheduled' end,
    to_jsonb(v_before), to_jsonb(v_after), nullif(trim(p_note), '')
  );

  return to_jsonb(v_after);
end;
$$;

create or replace function public.get_my_subscription_access()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_instructor_id uuid;
  v_subscription public.instructor_subscriptions%rowtype;
  v_effective_until date;
  v_termination_active boolean;
  v_kind text;
  v_notification public.subscription_notifications%rowtype;
  v_writable boolean;
  v_export_allowed boolean;
begin
  select id into v_instructor_id from public.instructor_profiles where user_id = auth.uid();
  if v_instructor_id is null then raise exception 'Instructor profile is required'; end if;

  select * into v_subscription from public.instructor_subscriptions where instructor_id = v_instructor_id;
  if v_subscription.id is null then
    return jsonb_build_object('plan', 'profile', 'status', 'trial', 'daysRemaining', null,
      'calendarWritable', true, 'exportAllowed', true, 'notification', null);
  end if;

  v_effective_until := greatest(v_subscription.valid_until, v_subscription.grace_until);
  v_termination_active := v_subscription.cancellation_effective_on is not null
    and current_date >= v_subscription.cancellation_effective_on;
  v_writable := not v_termination_active
    and v_subscription.status in ('trial', 'active')
    and (v_effective_until is null or current_date <= v_effective_until);
  v_export_allowed := v_writable
    or (v_termination_active and v_subscription.export_access_until is not null
      and current_date <= v_subscription.export_access_until);

  v_kind := case
    when v_termination_active then 'termination'
    when not v_writable then 'expired'
    when v_effective_until is not null and v_effective_until - current_date <= 3 then 'three_days'
    when v_effective_until is not null and v_effective_until - current_date <= 7 then 'seven_days'
    else null
  end;

  if v_kind is not null then
    insert into public.subscription_notifications (instructor_id, kind, effective_on)
    values (v_instructor_id, v_kind, current_date)
    on conflict (instructor_id, kind, effective_on) do nothing;
    select * into v_notification from public.subscription_notifications
    where instructor_id = v_instructor_id and kind = v_kind
      and effective_on = current_date and dismissed_at is null;
  end if;

  return jsonb_build_object(
    'subscriptionId', v_subscription.id, 'plan', v_subscription.plan, 'status', v_subscription.status,
    'paidAt', v_subscription.paid_at, 'periodMonths', v_subscription.period_months,
    'paidAmount', v_subscription.paid_amount, 'validUntil', v_subscription.valid_until,
    'graceUntil', v_subscription.grace_until, 'effectiveUntil', v_effective_until,
    'daysRemaining', case when v_effective_until is null then null else v_effective_until - current_date end,
    'calendarWritable', v_writable, 'exportAllowed', v_export_allowed,
    'terminationNoticeAt', v_subscription.cancellation_notice_at,
    'terminationEffectiveOn', v_subscription.cancellation_effective_on,
    'exportAccessUntil', v_subscription.export_access_until,
    'notification', case when v_notification.id is null then null else jsonb_build_object(
      'id', v_notification.id, 'kind', v_notification.kind,
      'effectiveOn', v_notification.effective_on, 'dismissedAt', v_notification.dismissed_at) end
  );
end;
$$;

-- Keep the existing dashboard contract and expose the new termination date.
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

revoke all on function public.manage_platform_subscription_termination(uuid, date, date, text) from public;
grant execute on function public.manage_platform_subscription_termination(uuid, date, date, text) to authenticated;
revoke all on function public.get_my_subscription_access() from public;
grant execute on function public.get_my_subscription_access() to authenticated;

comment on column public.instructor_subscriptions.cancellation_effective_on is
  'Date on which the calendar becomes read-only because the commercial agreement ended.';
