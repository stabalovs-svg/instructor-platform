-- Financial summary shown only through a valid personal student link.

create or replace function public.get_student_personal_finance(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_link public.student_schedule_links;
  v_charged numeric(10,2);
  v_paid numeric(10,2);
begin
  if p_token is null or length(p_token) <> 64 then return null; end if;

  select * into v_link
  from public.student_schedule_links
  where token_hash = digest(p_token, 'sha256')
    and enabled = true and revoked_at is null;

  if v_link.id is null then return null; end if;

  select coalesce(sum(l.price), 0) into v_charged
  from public.lessons l
  where l.student_id = v_link.student_id
    and l.instructor_id = v_link.instructor_id
    and l.status in ('completed', 'no_show')
    and l.chargeable = true
    and l.starts_at <= now();

  select coalesce(sum(p.amount), 0) into v_paid
  from public.payments p
  where p.student_id = v_link.student_id
    and p.instructor_id = v_link.instructor_id
    and p.voided_at is null;

  return jsonb_build_object(
    'chargedAmount', v_charged,
    'paidAmount', v_paid,
    'debtAmount', greatest(v_charged - v_paid, 0),
    'creditAmount', greatest(v_paid - v_charged, 0)
  );
end;
$$;

revoke all on function public.get_student_personal_finance(text) from public;
grant execute on function public.get_student_personal_finance(text) to anon, authenticated;

comment on function public.get_student_personal_finance(text) is
  'Returns charged, paid, debt and credit totals for one valid IKARS student link.';
