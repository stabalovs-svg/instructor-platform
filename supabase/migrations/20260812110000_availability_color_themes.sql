alter table public.availability_rules
  drop constraint if exists availability_rules_busy_color_check;

alter table public.availability_rules
  add constraint availability_rules_busy_color_check
  check (busy_color in ('warm', 'cool', 'pistachio', 'canary', 'peach'));
