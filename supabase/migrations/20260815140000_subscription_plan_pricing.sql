-- Centrally managed price matrix for Profile, Basic and Pro subscriptions.

create table if not exists public.subscription_plan_prices (
  plan public.instructor_plan not null,
  period_months smallint not null check (period_months in (1, 3, 6, 12)),
  total_amount numeric(10,2) not null check (total_amount >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (plan, period_months)
);

insert into public.subscription_plan_prices (plan, period_months, total_amount)
values
  ('profile', 1, 0), ('profile', 3, 0), ('profile', 6, 0), ('profile', 12, 0),
  ('basic', 1, 15), ('basic', 3, 42), ('basic', 6, 78), ('basic', 12, 144),
  ('pro', 1, 25), ('pro', 3, 69), ('pro', 6, 132), ('pro', 12, 240)
on conflict (plan, period_months) do nothing;

alter table public.subscription_plan_prices enable row level security;

create policy plan_prices_platform_admin_read on public.subscription_plan_prices
  for select to authenticated using (public.is_platform_admin());

create or replace function public.get_platform_plan_prices()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator access is required'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'plan', plan,
      'periodMonths', period_months,
      'totalAmount', total_amount,
      'updatedAt', updated_at
    ) order by array_position(array['profile','basic','pro'], plan::text), period_months)
    from public.subscription_plan_prices
  ), '[]'::jsonb);
end;
$$;

create or replace function public.save_platform_plan_prices(p_prices jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_plan public.instructor_plan;
  v_period smallint;
  v_amount numeric(10,2);
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator access is required'; end if;
  if jsonb_typeof(p_prices) <> 'array' or jsonb_array_length(p_prices) <> 12 then
    raise exception 'Complete price matrix is required';
  end if;

  for v_item in select value from jsonb_array_elements(p_prices)
  loop
    v_plan := (v_item->>'plan')::public.instructor_plan;
    v_period := (v_item->>'periodMonths')::smallint;
    v_amount := (v_item->>'totalAmount')::numeric(10,2);
    if v_period not in (1, 3, 6, 12) or v_amount < 0 then raise exception 'Invalid plan price'; end if;

    insert into public.subscription_plan_prices (plan, period_months, total_amount, updated_at, updated_by)
    values (v_plan, v_period, v_amount, now(), auth.uid())
    on conflict (plan, period_months) do update set
      total_amount = excluded.total_amount,
      updated_at = excluded.updated_at,
      updated_by = excluded.updated_by;
  end loop;

  insert into public.platform_admin_audit_log (actor_user_id, entity_type, action, after_data)
  values (auth.uid(), 'subscription_plan_prices', 'plan_prices_saved', p_prices);

  return public.get_platform_plan_prices();
end;
$$;

revoke all on function public.get_platform_plan_prices() from public;
revoke all on function public.save_platform_plan_prices(jsonb) from public;
grant execute on function public.get_platform_plan_prices() to authenticated;
grant execute on function public.save_platform_plan_prices(jsonb) to authenticated;

comment on table public.subscription_plan_prices is
  'Editable total subscription prices by plan and billing period; values are controlled only by IKARS platform administrators.';
