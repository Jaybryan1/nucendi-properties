
-- STRIPE MIGRATION: Run ONCE after the original schema.sql, on the existing database.
-- Keep manual Zelle review unchanged.
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check check(method in ('Zelle','Cash','Check','Bank transfer','Other','Stripe'));

create table if not exists public.stripe_checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  lease_id uuid not null references public.leases(id),
  tenant_id uuid not null references public.profiles(id),
  rent_month date not null check (extract(day from rent_month)=1),
  amount_cents bigint not null check(amount_cents > 0),
  stripe_session_id text unique,
  stripe_payment_intent_id text unique,
  state text not null default 'creating' check(state in ('creating','open','paid','failed','needs_review')),
  payment_id uuid unique references public.payments(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists stripe_sessions_lease_month_idx on public.stripe_checkout_sessions(lease_id,rent_month);
alter table public.stripe_checkout_sessions enable row level security;
-- Tenants can view their own sessions; only backend service-role can write.
create policy stripe_sessions_read on public.stripe_checkout_sessions for select to authenticated
using (tenant_id = (select auth.uid()) or public.is_admin());

-- Ensure tenant/admin browser clients cannot insert forged verified Stripe payments.
-- Existing tenant insert policy allows pending only; Stripe payments must also be service-only.
drop policy if exists payments_tenant_insert on public.payments;
create policy payments_tenant_insert on public.payments for insert to authenticated
with check(status='pending' and method <> 'Stripe' and reviewed_by is null and reviewed_at is null
and submitted_by=(select auth.uid()) and exists(select 1 from public.leases l
where l.id=payments.lease_id and l.tenant_id=(select auth.uid()) and l.active));

-- Backend-only atomic settlement. One transaction locks the lease and checks its balance.
create or replace function public.settle_stripe_checkout(
 p_session_id text, p_payment_intent_id text, p_amount_cents bigint, p_currency text
) returns text language plpgsql security definer set search_path = '' as $$
declare s public.stripe_checkout_sessions%rowtype; l public.leases%rowtype;
  paid_cents bigint; remaining_cents bigint; new_payment_id uuid;
begin
 select * into s from public.stripe_checkout_sessions where stripe_session_id=p_session_id for update;
 if not found then return 'unknown_session'; end if;
 if s.state='paid' then return 'already_paid'; end if;
 if s.state='needs_review' then return 'needs_review'; end if;
 if p_currency <> 'usd' or p_amount_cents <> s.amount_cents or p_payment_intent_id is null or p_payment_intent_id = '' then
   update public.stripe_checkout_sessions set state='needs_review',updated_at=now() where id=s.id;
   return 'needs_review';
 end if;
 select * into l from public.leases where id=s.lease_id for update;
 if not found or l.tenant_id<>s.tenant_id then
   update public.stripe_checkout_sessions set state='needs_review',updated_at=now() where id=s.id;
   return 'needs_review';
 end if;
 select coalesce(sum(round(amount*100)::bigint),0) into paid_cents from public.payments
 where lease_id=s.lease_id and rent_month=s.rent_month and status='verified';
 remaining_cents := greatest(0,round(l.monthly_rent*100)::bigint-paid_cents);
 if p_amount_cents > remaining_cents then
   update public.stripe_checkout_sessions set state='needs_review',stripe_payment_intent_id=p_payment_intent_id,updated_at=now() where id=s.id;
   return 'needs_review';
 end if;
 insert into public.payments(lease_id,submitted_by,amount,paid_on,rent_month,method,reference,notes,status,reviewed_at)
 values(s.lease_id,s.tenant_id,p_amount_cents::numeric/100,current_date,s.rent_month,'Stripe',p_payment_intent_id,'Automatically verified via Stripe signed webhook','verified',now())
 returning id into new_payment_id;
 update public.stripe_checkout_sessions set state='paid',payment_id=new_payment_id,stripe_payment_intent_id=p_payment_intent_id,updated_at=now() where id=s.id;
 return 'paid';
end;$$;
revoke all on function public.settle_stripe_checkout(text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.settle_stripe_checkout(text,text,bigint,text) to service_role;
