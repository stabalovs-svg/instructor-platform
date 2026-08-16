-- Optional instructor-specific subscription price without changing the global tariff matrix.

alter table public.instructor_subscriptions
  add column if not exists custom_total_amount numeric(10,2)
    check (custom_total_amount is null or custom_total_amount >= 0);

create or replace function public.save_platform_instructor_subscription_v2(
  p_instructor_id uuid,
  p_plan public.instructor_plan,
  p_status text,
  p_paid_at date,
  p_period_months smallint,
  p_paid_amount numeric,
  p_custom_total_amount numeric default null,
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
  v_valid_until date;
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator access is required'; end if;
  if p_status not in ('trial', 'active', 'paused', 'expired', 'cancelled') then raise exception 'Unsupported subscription status'; end if;
  if p_period_months not in (1, 3, 6, 12) then raise exception 'Unsupported payment period'; end if;
  if p_paid_amount < 0 then raise exception 'Paid amount cannot be negative'; end if;
  if p_custom_total_amount is not null and p_custom_total_amount < 0 then raise exception 'Custom price cannot be negative'; end if;

  select * into v_before from public.instructor_subscriptions where instructor_id = p_instructor_id;
  v_valid_until := case when p_paid_at is null then null else (p_paid_at + make_interval(months => p_period_months))::date end;

  insert into public.instructor_subscriptions (
    instructor_id, plan, status, paid_at, period_months, paid_amount,
    custom_total_amount, valid_until, grace_until, admin_note
  ) values (
    p_instructor_id, p_plan, p_status, p_paid_at, p_period_months, p_paid_amount,
    p_custom_total_amount, v_valid_until, null, nullif(trim(p_note), '')
  )
  on conflict (instructor_id) do update set
    plan = excluded.plan,
    status = excluded.status,
    paid_at = excluded.paid_at,
    period_months = excluded.period_months,
    paid_amount = excluded.paid_amount,
    custom_total_amount = excluded.custom_total_amount,
    valid_until = excluded.valid_until,
    grace_until = null,
    admin_note = excluded.admin_note
  returning * into v_after;

  update public.instructor_profiles set plan = p_plan where id = p_instructor_id;

  insert into public.platform_admin_audit_log (
    actor_user_id, instructor_id, entity_type, entity_id, action,
    before_data, after_data, reason
  ) values (
    auth.uid(), p_instructor_id, 'instructor_subscription', v_after.id,
    'subscription_saved', to_jsonb(v_before), to_jsonb(v_after), nullif(trim(p_note), '')
  );

  return to_jsonb(v_after);
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
      'standardAmount', price.total_amount, 'customAmount', sub.custom_total_amount,
      'agreedAmount', coalesce(sub.custom_total_amount, price.total_amount),
      'paidThrough', sub.valid_until, 'graceUntil', sub.grace_until,
      'terminationNoticeAt', sub.cancellation_notice_at,
      'terminationEffectiveOn', sub.cancellation_effective_on,
      'exportAccessUntil', sub.export_access_until, 'adminNote', sub.admin_note
    ) order by p.last_name, p.first_name) from public.instructor_profiles p
      left join public.instructor_subscriptions sub on sub.instructor_id = p.id
      left join public.subscription_plan_prices price on price.plan = coalesce(sub.plan, p.plan)
        and price.period_months = coalesce(sub.period_months, 1)), '[]'::jsonb),
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

revoke all on function public.save_platform_instructor_subscription_v2(uuid, public.instructor_plan, text, date, smallint, numeric, numeric, text) from public;
grant execute on function public.save_platform_instructor_subscription_v2(uuid, public.instructor_plan, text, date, smallint, numeric, numeric, text) to authenticated;

comment on column public.instructor_subscriptions.custom_total_amount is
  'Optional agreed total price for this instructor and billing period; null means use the standard plan price.';
