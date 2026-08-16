-- Student advance payments and allocations without double-counting income.

create table public.student_advance_allocations (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  check ((voided_at is null and void_reason is null) or (voided_at is not null and nullif(trim(void_reason), '') is not null))
);

create unique index student_advance_one_active_lesson_idx
  on public.student_advance_allocations (lesson_id) where voided_at is null;
create index student_advance_student_time_idx
  on public.student_advance_allocations (student_id, created_at desc);

alter table public.student_advance_allocations enable row level security;
grant select on table public.student_advance_allocations to authenticated;

create policy student_advance_owner_all on public.student_advance_allocations
  for all to authenticated
  using (public.owns_instructor(instructor_id))
  with check (public.owns_instructor(instructor_id));

create or replace function public.get_student_advance_balance(p_student_id uuid)
returns numeric
language sql
security definer
set search_path = public
as $$
  select case when public.owns_instructor(s.instructor_id) then
    greatest(
      coalesce((select sum(p.amount) from public.payments p
        where p.student_id = s.id and p.instructor_id = s.instructor_id
          and p.lesson_id is null and p.voided_at is null), 0)
      - coalesce((select sum(a.amount) from public.student_advance_allocations a
        where a.student_id = s.id and a.instructor_id = s.instructor_id
          and a.voided_at is null), 0),
      0
    )
  else null end
  from public.students s where s.id = p_student_id;
$$;

create or replace function public.record_student_advance(
  p_student_id uuid,
  p_amount numeric,
  p_method public.payment_method,
  p_paid_at timestamptz default now(),
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_instructor_id uuid;
  v_payment_id uuid;
begin
  select instructor_id into v_instructor_id from public.students
  where id = p_student_id and public.owns_instructor(instructor_id);
  if v_instructor_id is null then raise exception 'Student not found'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Advance amount must be positive'; end if;

  insert into public.payments (
    instructor_id, student_id, lesson_id, amount, method, paid_at, note, created_by
  ) values (
    v_instructor_id, p_student_id, null, p_amount, p_method,
    coalesce(p_paid_at, now()), nullif(trim(p_note), ''), auth.uid()
  ) returning id into v_payment_id;

  insert into public.audit_log (
    instructor_id, actor_user_id, entity_type, entity_id, action, after_data, reason
  ) values (
    v_instructor_id, auth.uid(), 'payment', v_payment_id, 'student_advance_recorded',
    jsonb_build_object('studentId', p_student_id, 'amount', p_amount, 'method', p_method),
    nullif(trim(p_note), '')
  );
  return v_payment_id;
end;
$$;

create or replace function public.allocate_student_advance(p_lesson_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson public.lessons;
  v_available numeric;
  v_existing public.student_advance_allocations;
  v_allocation_id uuid;
begin
  select * into v_lesson from public.lessons
  where id = p_lesson_id and public.owns_instructor(instructor_id);
  if v_lesson.id is null or v_lesson.student_id is null then raise exception 'Lesson or student not found'; end if;

  select * into v_existing from public.student_advance_allocations
  where lesson_id = p_lesson_id and voided_at is null;

  select public.get_student_advance_balance(v_lesson.student_id)
    + coalesce(v_existing.amount, 0) into v_available;
  if v_available < v_lesson.price then raise exception 'INSUFFICIENT_STUDENT_ADVANCE'; end if;

  if v_existing.id is not null then
    update public.student_advance_allocations
      set amount = v_lesson.price where id = v_existing.id
      returning id into v_allocation_id;
  else
    insert into public.student_advance_allocations (
      instructor_id, student_id, lesson_id, amount, created_by
    ) values (
      v_lesson.instructor_id, v_lesson.student_id, v_lesson.id, v_lesson.price, auth.uid()
    ) returning id into v_allocation_id;
  end if;

  insert into public.audit_log (
    instructor_id, actor_user_id, entity_type, entity_id, action, after_data
  ) values (
    v_lesson.instructor_id, auth.uid(), 'lesson', v_lesson.id, 'advance_allocated',
    jsonb_build_object('allocationId', v_allocation_id, 'amount', v_lesson.price)
  );
  return v_allocation_id;
end;
$$;

create or replace function public.void_student_advance_allocation(
  p_lesson_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allocation public.student_advance_allocations;
begin
  if nullif(trim(p_reason), '') is null then raise exception 'Reason is required'; end if;
  select * into v_allocation from public.student_advance_allocations
  where lesson_id = p_lesson_id and voided_at is null
    and public.owns_instructor(instructor_id);
  if v_allocation.id is null then return; end if;

  update public.student_advance_allocations
  set voided_at = now(), voided_by = auth.uid(), void_reason = trim(p_reason)
  where id = v_allocation.id;

  insert into public.audit_log (
    instructor_id, actor_user_id, entity_type, entity_id, action, before_data, reason
  ) values (
    v_allocation.instructor_id, auth.uid(), 'lesson', p_lesson_id,
    'advance_allocation_voided', to_jsonb(v_allocation), trim(p_reason)
  );
end;
$$;

create or replace function public.void_student_advance_payment(
  p_payment_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
  v_other_deposits numeric;
  v_allocated numeric;
begin
  if nullif(trim(p_reason), '') is null then raise exception 'Reason is required'; end if;
  select * into v_payment from public.payments
  where id = p_payment_id and lesson_id is null and voided_at is null
    and public.owns_instructor(instructor_id);
  if v_payment.id is null then raise exception 'Advance payment not found'; end if;

  select coalesce(sum(amount), 0) into v_other_deposits from public.payments
  where student_id = v_payment.student_id and instructor_id = v_payment.instructor_id
    and lesson_id is null and voided_at is null and id <> v_payment.id;
  select coalesce(sum(amount), 0) into v_allocated from public.student_advance_allocations
  where student_id = v_payment.student_id and instructor_id = v_payment.instructor_id
    and voided_at is null;
  if v_other_deposits < v_allocated then
    raise exception 'ADVANCE_PAYMENT_ALREADY_ALLOCATED';
  end if;

  update public.payments set
    voided_at = now(), voided_by = auth.uid(), void_reason = trim(p_reason)
  where id = v_payment.id;

  insert into public.audit_log (
    instructor_id, actor_user_id, entity_type, entity_id, action, before_data, reason
  ) values (
    v_payment.instructor_id, auth.uid(), 'payment', v_payment.id,
    'student_advance_voided', to_jsonb(v_payment), trim(p_reason)
  );
end;
$$;

revoke all on function public.get_student_advance_balance(uuid) from public;
revoke all on function public.record_student_advance(uuid, numeric, public.payment_method, timestamptz, text) from public;
revoke all on function public.allocate_student_advance(uuid) from public;
revoke all on function public.void_student_advance_allocation(uuid, text) from public;
revoke all on function public.void_student_advance_payment(uuid, text) from public;
grant execute on function public.get_student_advance_balance(uuid) to authenticated;
grant execute on function public.record_student_advance(uuid, numeric, public.payment_method, timestamptz, text) to authenticated;
grant execute on function public.allocate_student_advance(uuid) to authenticated;
grant execute on function public.void_student_advance_allocation(uuid, text) to authenticated;
grant execute on function public.void_student_advance_payment(uuid, text) to authenticated;

comment on table public.student_advance_allocations is
  'Allocates previously received student advance payments to lessons without adding income twice.';
