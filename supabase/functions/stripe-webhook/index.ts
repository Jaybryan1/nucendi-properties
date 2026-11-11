import Stripe from "npm:stripe@^22";
import { createClient } from "npm:@supabase/supabase-js@^2";
const stripe=new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!);
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const cryptoProvider=Stripe.createSubtleCryptoProvider();
Deno.serve(async req=>{
 if(req.method!=='POST') return new Response('Method not allowed',{status:405});
 const signature=req.headers.get('stripe-signature');
 if(!signature) return new Response('Missing signature',{status:400});
 let event:Stripe.Event;
 try{event=await stripe.webhooks.constructEventAsync(await req.text(),signature,Deno.env.get('STRIPE_WEBHOOK_SECRET')!,undefined,cryptoProvider)}
 catch(e){console.error('Invalid Stripe signature',e);return new Response('Invalid signature',{status:400})}
 try{
  if(event.type==='checkout.session.completed'||event.type==='checkout.session.async_payment_succeeded'){
   const session=event.data.object as Stripe.Checkout.Session;
   if(session.payment_status==='paid'){
    const {data,error}=await db.rpc('settle_stripe_checkout',{
      p_session_id:session.id,
      p_payment_intent_id:typeof session.payment_intent==='string'?session.payment_intent:session.payment_intent?.id??'',
      p_amount_cents:session.amount_total??0,p_currency:session.currency??''
    });
    if(error) throw error;
    console.log('Stripe settlement:',event.id,session.id,data);
    if(data==='unknown_session'||data==='needs_review') console.error('PAYMENT NEEDS ADMIN INVESTIGATION',session.id,data);
   }
  }else if(event.type==='checkout.session.async_payment_failed'){
   const session=event.data.object as Stripe.Checkout.Session;
   await db.from('stripe_checkout_sessions').update({state:'failed'}).eq('stripe_session_id',session.id).neq('state','paid');
  }else if(event.type==='charge.refunded'||event.type==='charge.dispute.created'){
   // Do not silently delete financial records; flag for admin handling.
   console.error('STRIPE REFUND OR DISPUTE REQUIRES ADMIN REVIEW',event.id,event.type);
  }
  return Response.json({received:true});
 }catch(e){console.error('Webhook processing error',e);return new Response('Processing failed',{status:500})}
});
