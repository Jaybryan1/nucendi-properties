# Nucendi Properties — Supabase tenant portal

A starter web application with tenant registration, admin-only property management, lease assignments, Zelle payment claims, admin confirmation, and row-level database security. **This is a starter implementation, not a production-ready financial or legal recordkeeping system.**

## Setup

1. Create a free project at https://supabase.com and wait for database provisioning.
2. Open **SQL Editor** and execute the entire `schema.sql` file once.
3. Open **Authentication → Providers → Email**. Enable email signups and preferably email confirmation. Configure email delivery for production. In **Authentication → URL Configuration**, set your deployed Site URL and allowed redirect URLs.
4. Create your own account through the website's **Tenant registration** form. Confirm your email and sign in. Then open SQL Editor and promote **only your own exact email** to admin:

   ```sql
   update public.profiles set role = 'admin' where email = 'YOUR_OWN_EMAIL@example.com';
   ```

   Verify exactly one account was promoted with `select id,email,role from public.profiles where role='admin';`. Sign out and sign back in.
5. Copy `config.example.js` to `config.js`. Paste **Project URL** and **anon/publishable key** from **Project Settings → API**. **Never use a service-role key in the frontend.**
6. Serve the directory with `python3 -m http.server 8080` and visit `http://localhost:8080`. Or upload `index.html` and `config.js` to GitHub Pages (use HTTPS). The `schema.sql` file does not need to be publicly hosted.
7. Add your four properties from the admin account. Tenants register with their own emails; you then assign them to a property and set monthly rent.
8. Tenant reports Zelle/bank payment; admin verifies actual receipt in the bank and clicks **Verify**. A claim is never treated as received rent until verified.

## Security / known limitations

- Supabase Row Level Security prevents tenant accounts from seeing unrelated properties, leases, profiles, and payments, and prevents tenants from approving claims or assigning themselves.
- A tenant can only insert a pending payment claim against their own active lease. Admins may verify or reject.
- The site does **not** collect money, connect to Zelle, confirm bank settlement, report to credit bureaus, or guarantee admissibility in court.
- MVP supports one active lease per tenant account; multiple occupants may each register, but assignment logic needs extension for joint tenancy.
- Current-month balances use one monthly rent amount and verified payments tagged to the same month. They do not calculate arrears, prorations, security deposits, credits, late fees, or lease-effective rent changes.
- Admin users can modify records; before relying on records as evidence, add append-only server-side audit events, signed receipt generation, immutable backups, change approval, and a retention policy.
- Before public production: add rate limiting/bot controls, robust transactional review RPCs, email configuration, data retention/deletion policy, tenant dispute handling, backups, monitoring, and professional security review.
- Browser uses the Supabase JavaScript client from a CDN; ensure it loads when online.
- The earlier browser-only prototype's localStorage data is **not** automatically migrated. Export it before switching and plan a validated migration separately.
