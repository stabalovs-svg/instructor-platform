-- Commercial subscriptions for the IKARS Instructor Platform.
-- This migration stores platform billing separately from instructor/student payments.

create table public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.instructor_subscriptions (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null unique references public.instructor_profiles(id) on delete cascade,
  plan public.instructor_plan not null default 'profile',
  status text not null default 'trial'
    check (status in ('trial', 'active', 'paused', 'expired', 'cancelled')),
  paid_at date,
  period_months smallint
    check (period_months is null or period_months in (1, 3, 6, 12)),
  paid_amount numeric(10,2)
    check (paid_amount is null or paid_amount >= 0),
  valid_until date,
  grace_until date,
  cancellation_notice_at timestamptz,
  export_access_until date,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (paid_at is null or valid_until is null or valid_until >= paid_at),
  check (grace_until is null or valid_until is null or grace_until >= valid_until)
);

create table public.subscription_payment_claims (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  claimed_at timestamptz not null default now(),
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'rejected')),
  instructor_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  check (
    (status = 'pending' and reviewed_at is null)
    or (status in ('confirmed', 'rejected') and reviewed_at is not null)
  )
);

create unique index subscription_payment_claims_one_pending_idx
  on public.subscription_payment_claims (instructor_id)
  where status = 'pending';

create table public.subscription_notifications (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  kind text not null
    check (kind in ('seven_days', 'three_days', 'expired', 'termination')),
  effective_on date not null default current_date,
  read_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (instructor_id, kind, effective_on),
  check (kind = 'seven_days' or dismissed_at is null)
);

create table public.platform_admin_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  instructor_id uuid references public.instructor_profiles(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index instructor_subscriptions_valid_until_idx
  on public.instructor_subscriptions (valid_until, status);
create index subscription_payment_claims_status_time_idx
  on public.subscription_payment_claims (status, claimed_at desc);
create index subscription_notifications_instructor_time_idx
  on public.subscription_notifications (instructor_id, created_at desc);
create index platform_admin_audit_time_idx
  on public.platform_admin_audit_log (created_at desc);

create trigger instructor_subscriptions_updated_at
  before update on public.instructor_subscriptions
  for each row execute function public.set_updated_at();

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins where user_id = auth.uid()
  );
$$;

create or replace function public.get_my_subscription_access()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with mine as (
    select s.*
    from public.instructor_subscriptions s
    join public.instructor_profiles p on p.id = s.instructor_id
    where p.user_id = auth.uid()
    limit 1
  )
  select coalesce(
    (
      select jsonb_build_object(
        'subscriptionId', id,
        'plan', plan,
        'status', status,
        'paidAt', paid_at,
        'periodMonths', period_months,
        'paidAmount', paid_amount,
        'validUntil', valid_until,
        'graceUntil', grace_until,
        'daysRemaining', case when valid_until is null then null else valid_until - current_date end,
        'calendarWritable', status in ('trial', 'active')
          and (valid_until is null or current_date <= coalesce(grace_until, valid_until)),
        'exportAllowed',
          (status in ('trial', 'active') and (valid_until is null or current_date <= coalesce(grace_until, valid_until)))
          or (export_access_until is not null and current_date <= export_access_until),
        'terminationNoticeAt', cancellation_notice_at
      )
      from mine
    ),
    jsonb_build_object(
      'plan', 'profile',
      'status', 'trial',
      'daysRemaining', null,
      'calendarWritable', true,
      'exportAllowed', true
    )
  );
$$;

create or replace function public.submit_subscription_payment_claim(p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_instructor_id uuid;
  v_claim_id uuid;
begin
  select id into v_instructor_id
  from public.instructor_profiles
  where user_id = auth.uid();

  if v_instructor_id is null then
    raise exception 'Instructor profile is required';
  end if;

  insert into public.subscription_payment_claims (instructor_id, instructor_note)
  values (v_instructor_id, nullif(trim(p_note), ''))
  returning id into v_claim_id;

  return v_claim_id;
exception
  when unique_violation then
    raise exception 'A pending payment claim already exists';
end;
$$;

create or replace function public.dismiss_my_subscription_notification(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.subscription_notifications n
  set dismissed_at = now(), read_at = coalesce(read_at, now())
  from public.instructor_profiles p
  where n.id = p_notification_id
    and n.instructor_id = p.id
    and p.user_id = auth.uid()
    and n.kind = 'seven_days'
    and n.dismissed_at is null;

  return found;
end;
$$;

revoke all on function public.is_platform_admin() from public;
revoke all on function public.get_my_subscription_access() from public;
revoke all on function public.submit_subscription_payment_claim(text) from public;
revoke all on function public.dismiss_my_subscription_notification(uuid) from public;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.get_my_subscription_access() to authenticated;
grant execute on function public.submit_subscription_payment_claim(text) to authenticated;
grant execute on function public.dismiss_my_subscription_notification(uuid) to authenticated;

alter table public.platform_admins enable row level security;
alter table public.instructor_subscriptions enable row level security;
alter table public.subscription_payment_claims enable row level security;
alter table public.subscription_notifications enable row level security;
alter table public.platform_admin_audit_log enable row level security;

create policy platform_admins_self_read on public.platform_admins
  for select to authenticated using (user_id = auth.uid());

create policy subscriptions_owner_read on public.instructor_subscriptions
  for select to authenticated using (public.owns_instructor(instructor_id));
create policy subscriptions_platform_admin_manage on public.instructor_subscriptions
  for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy payment_claims_owner_read on public.subscription_payment_claims
  for select to authenticated using (public.owns_instructor(instructor_id));
create policy payment_claims_platform_admin_manage on public.subscription_payment_claims
  for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy notifications_owner_read on public.subscription_notifications
  for select to authenticated using (public.owns_instructor(instructor_id));
create policy notifications_platform_admin_manage on public.subscription_notifications
  for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy platform_admin_audit_read on public.platform_admin_audit_log
  for select to authenticated using (public.is_platform_admin());
create policy platform_admin_audit_insert on public.platform_admin_audit_log
  for insert to authenticated with check (public.is_platform_admin() and actor_user_id = auth.uid());

comment on table public.instructor_subscriptions is
  'Commercial IKARS subscription state; separate from payments made by driving students.';
comment on function public.get_my_subscription_access() is
  'Returns server-derived calendar and export access for the signed-in instructor.';
comment on function public.submit_subscription_payment_claim(text) is
  'Creates one pending I-paid claim for the signed-in instructor.';
