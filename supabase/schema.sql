-- 8 Express database schema and access controls.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.shipments (
  id uuid primary key default gen_random_uuid(),
  tracking_number text not null unique,
  status text not null default 'Shipment registered',
  origin text,
  destination text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quote_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  details text not null,
  language text not null default 'es' check(language in('es','en')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.shipments enable row level security;
alter table public.quote_requests enable row level security;

-- Create a customer profile automatically whenever a user registers.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id,email,role)
  values(new.id,new.email,'customer')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- A narrowly scoped public tracking lookup; visitors cannot list shipments.
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

-- Used by policies to verify staff without recursive profile-table RLS.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Profiles: users can read their own profile; admins can manage all profiles.
drop policy if exists "Read own profile or admin" on public.profiles;
create policy "Read own profile or admin" on public.profiles
for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "Admins manage profiles" on public.profiles;
create policy "Admins manage profiles" on public.profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Shipments: only admins can read the full table or make changes.
drop policy if exists "Public can look up shipment tracking" on public.shipments;
drop policy if exists "Admins manage shipments" on public.shipments;
create policy "Admins manage shipments" on public.shipments
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Visitors can submit quote requests; only admins can review/manage them.
drop policy if exists "Visitors can submit quote requests" on public.quote_requests;
drop policy if exists "Admins manage quote requests" on public.quote_requests;
create policy "Visitors can submit quote requests" on public.quote_requests
for insert to anon,authenticated
with check (
  char_length(trim(name)) between 1 and 120
  and char_length(trim(email)) between 3 and 254
  and char_length(trim(details)) between 1 and 3000
  and language in('es','en')
);
create policy "Admins manage quote requests" on public.quote_requests
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- No public shipment writes and no self-service role changes are permitted.
