import Stripe from "npm:stripe@^22";
import { createClient } from "npm:@supabase/supabase-js@^2";
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const headers = { "Access-Control-Allow-Origin": new URL(Deno.env.get("APP_URL")!).origin, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
const respond = (body: unknown, status=200) => new Response(JSON.stringify(body), {status,headers});
Deno.serve(async req => {
 if(req.method==='OPTIONS') return new Response(null,{status:204,headers});
 if(req.method!=='POST') return respond({error:'Method not allowed'},405);
 const authorization=req.headers.get('authorization');
 if(!authorization?.startsWith('Bearer ')) return respond({error:'Unauthorized'},401);
 const client=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
 const {data:{user},error:authError}=await client.auth.getUser(authorization.slice(7));
 if(authError||!user) return respond({error:'Unauthorized'},401);
 try {
  const {rentMonth}=await req.json();
  if(typeof rentMonth!=='string'||!/^\d{4}-(0[1-9]|1[0-2])$/.test(rentMonth)) return respond({error:'Invalid rent month'},400);
  const month=rentMonth+'-01';
  const {data:lease,error:leaseError}=await client.from('leases').select('id,tenant_id,monthly_rent,active').eq('tenant_id',user.id).eq('active',true).single();
  if(leaseError||!lease) return respond({error:'No active lease'},400);
  // Server-side calculation: client never chooses amount or lease.
  const {data:payments,error:paymentsError}=await service.from('payments').select('amount').eq('lease_id',lease.id).eq('rent_month',month).eq('status','verified');
  if(paymentsError) throw paymentsError;
  const paidCents=(payments||[]).reduce((n,p)=>n+Math.round(Number(p.amount)*100),0);
  const balanceCents=Math.max(0,Math.round(Number(lease.monthly_rent)*100)-paidCents);
  if(!balanceCents) return respond({error:'No outstanding balance for this month'},400);
  // One open checkout per lease/month prevents casual duplicate checkout creation.
  // Paid sessions are reconciled atomically by the webhook.
  const {data:existing,error:existingError}=await service.from('stripe_checkout_sessions').select('id,stripe_session_id,state').eq('lease_id',lease.id).eq('rent_month',month).in('state',['creating','open']).order('created_at',{ascending:false}).limit(1);
  if(existingError) throw existingError;
  if(existing?.length){
   if(!existing[0].stripe_session_id) return respond({error:'Checkout is being prepared. Retry shortly.'},409);
   const previous=await stripe.checkout.sessions.retrieve(existing[0].stripe_session_id);
   if(previous.status==='open'&&previous.url) return respond({url:previous.url});
   await service.from('stripe_checkout_sessions').update({state:'failed'}).eq('id',existing[0].id);
  }
  const {data:record,error:insertError}=await service.from('stripe_checkout_sessions').insert({lease_id:lease.id,tenant_id:user.id,rent_month:month,amount_cents:balanceCents}).select('id').single();
  if(insertError) throw insertError;
  const appUrl=Deno.env.get('APP_URL')!;
  const session=await stripe.checkout.sessions.create({
   mode:'payment',payment_method_types:['card'],
   line_items:[{price_data:{currency:'usd',unit_amount:balanceCents,product_data:{name:`Nucendi Properties rent - ${rentMonth}`}},quantity:1}],
   client_reference_id:record.id,metadata:{checkout_record_id:record.id},
   success_url:`${appUrl}/?stripe=success`,cancel_url:`${appUrl}/?stripe=cancelled`,
  },{idempotencyKey:`nucendi-checkout-${record.id}`});
  const {error:updateError}=await service.from('stripe_checkout_sessions').update({stripe_session_id:session.id,state:'open'}).eq('id',record.id);
  if(updateError) throw updateError;
  return respond({url:session.url});
 } catch(e){console.error('Checkout error',e);return respond({error:'Could not create checkout'},500)}
});
