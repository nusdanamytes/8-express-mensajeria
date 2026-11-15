-- 8 Express admin operations upgrade
-- Run this entire file in Supabase SQL Editor. Safe for existing shipment records.

alter table public.shipments
  add column if not exists shipping_date date,
  add column if not exists sender_name text,
  add column if not exists receiver_name text,
  add column if not exists receiver_email text,
  add column if not exists current_location text,
  add column if not exists package_details text,
  add column if not exists latest_update text;

create unique index if not exists shipments_tracking_number_unique
  on public.shipments(tracking_number);

create or replace function public.assign_8express_tracking_number()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.tracking_number is null or btrim(new.tracking_number)='' then
    new.tracking_number := '8EXP-' || to_char(current_date,'YYYYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  end if;
  return new;
end;
$$;

drop trigger if exists set_8express_tracking_number on public.shipments;
create trigger set_8express_tracking_number
before insert on public.shipments
for each row execute function public.assign_8express_tracking_number();

-- Dated tracking milestones entered by authorized staff.
create table if not exists public.shipment_events (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  event_title text not null,
  event_description text,
  location text,
  event_time timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists shipment_events_shipment_time_idx
  on public.shipment_events(shipment_id,event_time asc);
alter table public.shipment_events enable row level security;

drop policy if exists "8 Express admins read shipment events" on public.shipment_events;
create policy "8 Express admins read shipment events" on public.shipment_events
for select to authenticated using (public.is_admin());
drop policy if exists "8 Express admins add shipment events" on public.shipment_events;
create policy "8 Express admins add shipment events" on public.shipment_events
for insert to authenticated with check (public.is_admin());
drop policy if exists "8 Express admins delete shipment events" on public.shipment_events;
create policy "8 Express admins delete shipment events" on public.shipment_events
for delete to authenticated using (public.is_admin());

-- Admin-configurable customer support contact.
create table if not exists public.express_settings (
  setting_key text primary key,
  setting_value text not null,
  updated_at timestamptz not null default now()
);
alter table public.express_settings enable row level security;
drop policy if exists "8 Express admins read settings" on public.express_settings;
create policy "8 Express admins read settings" on public.express_settings
for select to authenticated using (public.is_admin());
drop policy if exists "8 Express admins insert settings" on public.express_settings;
create policy "8 Express admins insert settings" on public.express_settings
for insert to authenticated with check (public.is_admin());
drop policy if exists "8 Express admins update settings" on public.express_settings;
create policy "8 Express admins update settings" on public.express_settings
for update to authenticated using (public.is_admin()) with check (public.is_admin());
grant select,insert,update on public.express_settings to authenticated;

-- Public tracking exposes only safe operational fields, not sender/receiver or cargo data.
drop function if exists public.track_shipment(text);
create function public.track_shipment(p_tracking_number text)
returns table(
  tracking_number text,status text,origin text,destination text,updated_at timestamptz,
  current_location text,latest_update text,shipping_date date
)
language sql stable security definer set search_path=public as $$
  select s.tracking_number,s.status,s.origin,s.destination,s.updated_at,
         s.current_location,s.latest_update,s.shipping_date
  from public.shipments s
  where upper(trim(s.tracking_number))=upper(trim(p_tracking_number))
  limit 1;
$$;
revoke all on function public.track_shipment(text) from public;
grant execute on function public.track_shipment(text) to anon,authenticated;

create or replace function public.track_shipment_events(p_tracking_number text)
returns table(event_title text,event_description text,location text,event_time timestamptz)
language sql stable security definer set search_path=public as $$
  select e.event_title,e.event_description,e.location,e.event_time
  from public.shipment_events e
  join public.shipments s on s.id=e.shipment_id
  where upper(trim(s.tracking_number))=upper(trim(p_tracking_number))
  order by e.event_time asc;
$$;
revoke all on function public.track_shipment_events(text) from public;
grant execute on function public.track_shipment_events(text) to anon,authenticated;

create or replace function public.track_shipment_support(p_tracking_number text)
returns table(support_email text)
language sql stable security definer set search_path=public as $$
  select st.setting_value
  from public.shipments s
  join public.express_settings st on st.setting_key='support_email'
  where upper(trim(s.tracking_number))=upper(trim(p_tracking_number))
    and lower(coalesce(s.status,'')) like '%hold%'
    and length(trim(st.setting_value))>0
  limit 1;
$$;
revoke all on function public.track_shipment_support(text) from public;
grant execute on function public.track_shipment_support(text) to anon,authenticated;
