# 8 Express Mensajería y Paquetería

Spanish-first bilingual courier and parcel website built with React, Vite and Supabase.

## Local development
1. Install Node.js LTS.
2. Clone this repository and run `npm install`.
3. Copy `.env.example` to `.env.local`.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
5. Run `npm run dev`.

## Supabase
Run `supabase/schema.sql` in the Supabase SQL Editor. It creates public tracking lookup and quote-request tables. Public users cannot create or modify shipments. Staff authentication and admin-only management will be added in the next stage.

## Vercel
Import this repository into Vercel and set the two Vite environment variables above before deploying.

## Company
8 Express Mensajería y Paquetería  
C. del Fresno 91, Sta. María la Ribera, Cuauhtémoc, 06400 Ciudad de México, CDMX, Mexico.

Phone number will be added when supplied. Never expose a Supabase service-role key or database password in frontend code.
