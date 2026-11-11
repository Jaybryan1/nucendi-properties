-- Run in Supabase SQL Editor. Create the first admin using the command in README.
create extension if not exists pgcrypto;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, email text not null, full_name text not null default '', role text not null default 'tenant' check(role in ('admin','tenant')), created_at timestamptz not null default now());
create table public.properties (id uuid primary key default gen_random_uuid(), name text not null, address text not null default '', created_at timestamptz not null default now());
create table public.leases (id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.profiles(id), property_id uuid not null references public.properties(id), monthly_rent numeric(12,2) not null check(monthly_rent>=0), due_day int not null default 1 check(due_day between 1 and 28), active boolean not null default true, created_at timestamptz not null default now());
create unique index one_active_lease_per_tenant on public.leases(tenant_id) where active;
create table public.payments (id uuid primary key default gen_random_uuid(), lease_id uuid not null references public.leases(id), submitted_by uuid references public.profiles(id), amount numeric(12,2) not null check(amount>0), paid_on date not null, rent_month date not null check(extract(day from rent_month)=1), method text not null check(method in ('Zelle','Cash','Check','Bank transfer','Other')), reference text not null default '', notes text not null default '', status text not null default 'pending' check(status in ('pending','verified','rejected')), reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, created_at timestamptz not null default now());
create index leases_property_idx on public.leases(property_id);
create index payments_lease_idx on public.payments(lease_id);
create or replace function public.create_profile() returns trigger language plpgsql security definer set search_path = '' as $$begin insert into public.profiles(id,email,full_name) values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name','')); return new; end;$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.create_profile();
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin');$$;
revoke all on function public.is_admin() from public; grant execute on function public.is_admin() to authenticated;
alter table public.profiles enable row level security;
alter table public.properties enable row level security;
alter table public.leases enable row level security;
alter table public.payments enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or public.is_admin());
create policy profile_admin_update on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy properties_read on public.properties for select to authenticated using(public.is_admin() or exists(select 1 from public.leases l where l.property_id=properties.id and l.tenant_id=(select auth.uid())));
create policy properties_admin_insert on public.properties for insert to authenticated with check(public.is_admin());
create policy properties_admin_update on public.properties for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy leases_read on public.leases for select to authenticated using(public.is_admin() or tenant_id=(select auth.uid()));
create policy leases_admin_insert on public.leases for insert to authenticated with check(public.is_admin());
create policy leases_admin_update on public.leases for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy payments_read on public.payments for select to authenticated using(public.is_admin() or exists(select 1 from public.leases l where l.id=payments.lease_id and l.tenant_id=(select auth.uid())));
-- Tenant submissions are forced to pending, their own lease, and their own identity.
create policy payments_tenant_insert on public.payments for insert to authenticated with check(status='pending' and reviewed_by is null and reviewed_at is null and submitted_by=(select auth.uid()) and exists(select 1 from public.leases l where l.id=payments.lease_id and l.tenant_id=(select auth.uid()) and l.active));
create policy payments_admin_insert on public.payments for insert to authenticated with check(public.is_admin());
create policy payments_admin_update on public.payments for update to authenticated using(public.is_admin()) with check(public.is_admin());
-- Prevent accidental tenant deletion and keep payment history immutable in the UI.
-- IMPORTANT: An admin account is a privileged trusted user. Audit logging should be added before legal-evidence use.
