-- Preserve the pending payment-claim state across logout, login and page reload.

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
  v_payment_claim_pending boolean;
  v_kind text;
  v_notification public.subscription_notifications%rowtype;
  v_writable boolean;
  v_export_allowed boolean;
begin
  select id into v_instructor_id from public.instructor_profiles where user_id = auth.uid();
  if v_instructor_id is null then raise exception 'Instructor profile is required'; end if;

  select exists(
    select 1 from public.subscription_payment_claims
    where instructor_id = v_instructor_id and status = 'pending'
  ) into v_payment_claim_pending;

  select * into v_subscription from public.instructor_subscriptions where instructor_id = v_instructor_id;
  if v_subscription.id is null then
    return jsonb_build_object(
      'plan', 'profile', 'status', 'trial', 'daysRemaining', null,
      'calendarWritable', true, 'exportAllowed', true,
      'paymentClaimPending', v_payment_claim_pending, 'notification', null
    );
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
    'paymentClaimPending', v_payment_claim_pending,
    'terminationNoticeAt', v_subscription.cancellation_notice_at,
    'terminationEffectiveOn', v_subscription.cancellation_effective_on,
    'exportAccessUntil', v_subscription.export_access_until,
    'notification', case when v_notification.id is null then null else jsonb_build_object(
      'id', v_notification.id, 'kind', v_notification.kind,
      'effectiveOn', v_notification.effective_on, 'dismissedAt', v_notification.dismissed_at) end
  );
end;
$$;

revoke all on function public.get_my_subscription_access() from public;
grant execute on function public.get_my_subscription_access() to authenticated;
