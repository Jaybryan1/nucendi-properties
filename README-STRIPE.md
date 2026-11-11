# Nucendi Properties — Stripe Sandbox integration

This package extends the **uploaded** Nucendi Properties Supabase app. Zelle/manual verification remains available.

## 1. Database migration

Run `stripe-migration.sql` in **your existing Supabase project's SQL Editor**. Do not rerun the original `schema.sql` against a populated project.

## 2. Edge Function secrets

In Supabase → Edge Functions → Secrets, configure:

- `STRIPE_SECRET_KEY`: Stripe **Sandbox** `sk_test_...` key
- `STRIPE_WEBHOOK_SECRET`: the `whsec_...` secret from your **Sandbox event destination**
- `APP_URL`: exact public website origin, e.g. `https://example.github.io` (for GitHub Pages subpath use full site path without trailing slash, e.g. `https://example.github.io/nucendi-properties`)

Supabase automatically provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. **Never place the service role or Stripe secret keys in config.js or frontend code.**

## 3. Deploy

Using the Supabase CLI from this folder:

```bash
npx supabase login
npx supabase link --project-ref jtvfegtzwpbtnoiumigu
npx supabase functions deploy create-checkout-session
npx supabase functions deploy stripe-webhook --no-verify-jwt
```

You can also paste each function's `index.ts` into the Supabase Dashboard Edge Function editor and deploy there. For `stripe-webhook`, turn **Verify JWT OFF**. Leave JWT verification ON for `create-checkout-session`.

Your Stripe webhook URL remains:

`https://jtvfegtzwpbtnoiumigu.supabase.co/functions/v1/stripe-webhook`

Subscribe to Snapshot events `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `charge.refunded`, `charge.dispute.created`.

## 4. Frontend

Keep your existing `config.js` (with **public** Supabase URL and anon key only). Publish the updated `index.html` and your `config.js` on your hosting platform. Never upload `.env` or private credentials.

Tenant logs in → Payments → chooses rent month → Pay outstanding rent with Stripe → Stripe Sandbox Checkout. Upon successful webhook, a **verified** `payments` row is inserted and existing overview totals update after refresh.

## 5. Test

Use a real Sandbox Checkout flow (test card `4242 4242 4242 4242`, future expiration, any CVC). A generic `stripe trigger checkout.session.completed` fixture does **not** match a locally created checkout record and cannot validate rent posting. After Checkout, confirm the payment row in `payments` and `stripe_checkout_sessions` state `paid`.

## Important limitations before real-money launch

- Rent calculations are based on **one monthly rent per lease**, not arrears, credits, prorations, or deposits. Tenant can select a month; the system does not validate whether the selected month is due under lease terms.
- If multiple checkouts or a manual payment occur concurrently, the atomic settlement function **does not over-credit** a lease; an excess payment is flagged `needs_review` and requires an administrator to investigate and refund/allocate it manually. Two rapid simultaneous checkout creation requests can still create two sessions; add a DB reservation/locking workflow before production.
- Refunds/disputes currently generate **server logs only**; implement durable refund/dispute tracking and manual reconciliation before real money.
- Existing manual admin powers can change verified payment records. For production financial recordkeeping, implement immutable audit trails and stronger administrative controls.
- Verify test and live webhook keys are not mixed. Stripe processing fees apply to live card transactions.
- Security and financial compliance review is recommended before production.
