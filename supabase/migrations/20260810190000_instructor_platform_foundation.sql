-- IKARS Instructor Platform foundation.
-- This migration is prepared locally and must only be applied to a dedicated
-- test project created for the instructor platform.

create extension if not exists btree_gist;

create type public.instructor_plan as enum ('profile', 'basic', 'pro');
create type public.record_status as enum ('active', 'paused', 'archived');
create type public.school_link_status as enum ('invited', 'active', 'paused', 'ended');
create type public.transmission_type as enum ('manual', 'automatic');
create type public.lesson_status as enum ('planned', 'completed', 'cancelled', 'no_show');
create type public.payment_method as enum ('cash', 'transfer', 'school');
create type public.widget_event_type as enum ('widget_view', 'instructor_profile_view', 'phone_click', 'filter_used', 'session_end');

create table public.instructor_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 80),
  last_name text not null check (char_length(last_name) between 1 and 80),
  phone text,
  email text,
  languages text[] not null default array['lv']::text[],
  categories text[] not null default array['B']::text[],
  description text,
  qualification_number text,
  qualification_valid_until date,
  plan public.instructor_plan not null default 'profile',
  status public.record_status not null default 'active',
  timezone text not null default 'Europe/Riga',
  is_public boolean not null default false,
  public_phone boolean not null default true,
  calendar_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.driving_schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  registration_number text,
  email text,
  phone text,
  website_url text,
  logo_url text,
  status public.record_status not null default 'active',
  widget_settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.school_members (
  school_id uuid not null references public.driving_schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'admin' check (role in ('admin', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (school_id, user_id)
);

create table public.school_instructor_links (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.driving_schools(id) on delete cascade,
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  status public.school_link_status not null default 'invited',
  show_in_widget boolean not null default false,
  started_at date,
  ended_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, instructor_id)
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  make text not null,
  model text not null,
  production_year smallint check (production_year between 1980 and 2100),
  transmission public.transmission_type not null,
  registration_number text,
  lesson_price numeric(10,2) not null check (lesson_price >= 0),
  weekend_price numeric(10,2) check (weekend_price >= 0),
  photo_url text,
  is_active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.meeting_points (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  city text not null default 'Rīga',
  district text,
  public_name text not null,
  directions text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  surcharge numeric(10,2) not null default 0 check (surcharge >= 0),
  is_active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  phone text,
  email text,
  school_name text,
  preferred_vehicle_id uuid references public.vehicles(id) on delete set null,
  lesson_price numeric(10,2) check (lesson_price >= 0),
  notes text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.availability_rules (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null unique references public.instructor_profiles(id) on delete cascade,
  enabled_weekdays smallint[] not null default array[1,2,3,4,5]::smallint[],
  first_lesson time not null default '06:00',
  last_lesson time not null default '21:00',
  slot_minutes smallint not null default 90 check (slot_minutes in (60, 90)),
  public_horizon_days smallint not null default 42 check (public_horizon_days between 7 and 180),
  free_color text not null default 'mint' check (free_color in ('mint', 'outline')),
  busy_color text not null default 'warm' check (busy_color in ('warm', 'cool')),
  updated_at timestamptz not null default now(),
  check (last_lesson >= first_lesson),
  check (enabled_weekdays <@ array[0,1,2,3,4,5,6]::smallint[])
);

create table public.calendar_blocks (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  student_id uuid references public.students(id) on delete set null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  meeting_point_id uuid references public.meeting_points(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  service_type text not null default 'lesson' check (service_type in ('lesson', 'exam')),
  status public.lesson_status not null default 'planned',
  chargeable boolean not null default false,
  price numeric(10,2) not null check (price >= 0),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  constraint lessons_no_instructor_overlap exclude using gist (
    instructor_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('planned', 'completed', 'no_show'))
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  student_id uuid references public.students(id) on delete set null,
  lesson_id uuid references public.lessons(id) on delete set null,
  amount numeric(10,2) not null check (amount > 0),
  method public.payment_method not null,
  paid_at timestamptz not null default now(),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  check ((voided_at is null and void_reason is null) or (voided_at is not null and nullif(trim(void_reason), '') is not null))
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  instructor_id uuid not null references public.instructor_profiles(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create table public.widget_events (
  id bigint generated always as identity primary key,
  event_type public.widget_event_type not null,
  occurred_at timestamptz not null default now(),
  source text not null default 'catalog',
  school_id uuid references public.driving_schools(id) on delete set null,
  instructor_id uuid references public.instructor_profiles(id) on delete set null,
  anonymous_session_id uuid not null,
  active_seconds integer check (active_seconds between 0 and 86400),
  language text check (language in ('lv', 'ru')),
  device_type text check (device_type in ('mobile', 'tablet', 'desktop')),
  metadata jsonb not null default '{}'::jsonb
);

alter table public.vehicles add constraint vehicles_id_instructor_unique unique (id, instructor_id);
alter table public.meeting_points add constraint meeting_points_id_instructor_unique unique (id, instructor_id);
alter table public.students add constraint students_id_instructor_unique unique (id, instructor_id);
alter table public.lessons add constraint lessons_id_instructor_unique unique (id, instructor_id);

alter table public.students add constraint students_vehicle_same_instructor
  foreign key (preferred_vehicle_id, instructor_id)
  references public.vehicles (id, instructor_id);
alter table public.lessons add constraint lessons_student_same_instructor
  foreign key (student_id, instructor_id)
  references public.students (id, instructor_id);
alter table public.lessons add constraint lessons_vehicle_same_instructor
  foreign key (vehicle_id, instructor_id)
  references public.vehicles (id, instructor_id);
alter table public.lessons add constraint lessons_meeting_point_same_instructor
  foreign key (meeting_point_id, instructor_id)
  references public.meeting_points (id, instructor_id);
alter table public.payments add constraint payments_student_same_instructor
  foreign key (student_id, instructor_id)
  references public.students (id, instructor_id);
alter table public.payments add constraint payments_lesson_same_instructor
  foreign key (lesson_id, instructor_id)
  references public.lessons (id, instructor_id);

create index students_instructor_name_idx on public.students (instructor_id, last_name, first_name);
create index lessons_instructor_start_idx on public.lessons (instructor_id, starts_at);
create index payments_instructor_paid_idx on public.payments (instructor_id, paid_at desc);
create index audit_log_instructor_time_idx on public.audit_log (instructor_id, created_at desc);
create index widget_events_instructor_time_idx on public.widget_events (instructor_id, occurred_at desc);
create index widget_events_school_time_idx on public.widget_events (school_id, occurred_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger instructor_profiles_updated_at before update on public.instructor_profiles
  for each row execute function public.set_updated_at();
create trigger driving_schools_updated_at before update on public.driving_schools
  for each row execute function public.set_updated_at();
create trigger school_instructor_links_updated_at before update on public.school_instructor_links
  for each row execute function public.set_updated_at();
create trigger vehicles_updated_at before update on public.vehicles
  for each row execute function public.set_updated_at();
create trigger meeting_points_updated_at before update on public.meeting_points
  for each row execute function public.set_updated_at();
create trigger students_updated_at before update on public.students
  for each row execute function public.set_updated_at();
create trigger availability_rules_updated_at before update on public.availability_rules
  for each row execute function public.set_updated_at();
create trigger lessons_updated_at before update on public.lessons
  for each row execute function public.set_updated_at();

create or replace function public.audit_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (
    instructor_id, actor_user_id, entity_type, entity_id, action,
    before_data, after_data, reason
  ) values (
    new.instructor_id,
    auth.uid(),
    'payment',
    new.id,
    case when tg_op = 'INSERT' then 'created'
         when old.voided_at is null and new.voided_at is not null then 'voided'
         else 'updated' end,
    case when tg_op = 'UPDATE' then to_jsonb(old) end,
    to_jsonb(new),
    new.void_reason
  );
  return new;
end;
$$;

create trigger payments_audit after insert or update on public.payments
  for each row execute function public.audit_payment_change();

create or replace function public.owns_instructor(target_instructor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.instructor_profiles
    where id = target_instructor_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_school_member(target_school_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.school_members
    where school_id = target_school_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_school_admin(target_school_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.school_members
    where school_id = target_school_id and user_id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.owns_instructor(uuid) from public;
revoke all on function public.is_school_member(uuid) from public;
revoke all on function public.is_school_admin(uuid) from public;
grant execute on function public.owns_instructor(uuid) to authenticated;
grant execute on function public.is_school_member(uuid) to authenticated;
grant execute on function public.is_school_admin(uuid) to authenticated;

alter table public.instructor_profiles enable row level security;
alter table public.driving_schools enable row level security;
alter table public.school_members enable row level security;
alter table public.school_instructor_links enable row level security;
alter table public.vehicles enable row level security;
alter table public.meeting_points enable row level security;
alter table public.students enable row level security;
alter table public.availability_rules enable row level security;
alter table public.calendar_blocks enable row level security;
alter table public.lessons enable row level security;
alter table public.payments enable row level security;
alter table public.audit_log enable row level security;
alter table public.widget_events enable row level security;

create policy instructor_profile_owner on public.instructor_profiles
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy school_member_read on public.driving_schools
  for select to authenticated using (public.is_school_member(id));
create policy school_admin_update on public.driving_schools
  for update to authenticated using (public.is_school_admin(id)) with check (public.is_school_admin(id));

create policy school_members_read on public.school_members
  for select to authenticated using (public.is_school_member(school_id));

create policy school_links_instructor_read on public.school_instructor_links
  for select to authenticated using (public.owns_instructor(instructor_id) or public.is_school_member(school_id));
create policy school_links_school_manage on public.school_instructor_links
  for all to authenticated using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));

create policy vehicles_owner on public.vehicles
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy meeting_points_owner on public.meeting_points
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy students_owner on public.students
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy availability_owner on public.availability_rules
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy calendar_blocks_owner on public.calendar_blocks
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy lessons_owner on public.lessons
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy payments_owner on public.payments
  for all to authenticated using (public.owns_instructor(instructor_id)) with check (public.owns_instructor(instructor_id));
create policy audit_log_owner_read on public.audit_log
  for select to authenticated using (public.owns_instructor(instructor_id));

create policy widget_events_instructor_read on public.widget_events
  for select to authenticated using (
    (instructor_id is not null and public.owns_instructor(instructor_id))
    or (school_id is not null and public.is_school_member(school_id))
  );

comment on table public.widget_events is
  'Anonymous widget analytics. A phone_click records an attempted call action, not a confirmed conversation.';
