-- 8 Express initial schema. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.shipments(id uuid primary key default gen_random_uuid(),tracking_number text not null unique,status text not null default 'Shipment registered',origin text,destination text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.quote_requests(id uuid primary key default gen_random_uuid(),name text not null,email text not null,details text not null,language text not null default 'es' check(language in('es','en')),created_at timestamptz not null default now());
alter table public.shipments enable row level security;
alter table public.quote_requests enable row level security;

-- Public tracking is performed through a narrowly scoped function. Visitors cannot list shipments.
drop policy if exists "Public can look up shipment tracking" on public.shipments;
drop policy if exists "Visitors can submit quote requests" on public.quote_requests;
create policy "Visitors can submit quote requests" on public.quote_requests
for insert to anon,authenticated
with check(char_length(trim(name)) between 1 and 120 and char_length(trim(email)) between 3 and 254 and char_length(trim(details)) between 1 and 3000 and language in('es','en'));

create or replace function public.track_shipment(p_tracking_number text)
returns table(tracking_number text,status text,origin text,destination text,updated_at timestamptz)
language sql
security definer
set search_path = ''
as $$
  select s.tracking_number,s.status,s.origin,s.destination,s.updated_at
  from public.shipments as s
  where s.tracking_number = upper(trim(p_tracking_number))
  limit 1;
$$;
revoke all on function public.track_shipment(text) from public;
grant execute on function public.track_shipment(text) to anon,authenticated;

-- No public write policies for shipments. Staff-only management will be added with admin authentication.
