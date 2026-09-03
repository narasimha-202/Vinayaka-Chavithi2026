# Production Deployment Guide — Sri Gowri Putra Youth Management System

This guide outlines step-by-step instructions to configure Supabase and deploy the Sri Gowri Putra Youth — Vinayaka Chavithi Management System web application to production on Netlify.

---

## 1. Supabase Cloud Configuration

### Step 1: Create a Free Supabase Project
1. Sign up or log into [Supabase](https://supabase.com/).
2. Create a new project named `sgpy-vinayaka-chavithi`.
3. Copy your **Project URL** and **API Key (anon / public)** from `Project Settings -> API`.

### Step 2: Database Setup & SQL Migration
1. Go to your Supabase project dashboard -> **SQL Editor**.
2. Create a **New Query**.
3. Paste the contents of `SUPABASE_PRODUCTION_SETUP.sql`.
4. Click **Run** to execute the SQL script. This creates all tables (`user_profiles`, `v2_data`, `donations`, `expenses`, `committee_members`, `sponsors`, `prasadam`, `events`, `v2_gallery_photos`, `audit_logs`), Row Level Security (RLS) policies, RPC helper functions, and enables Realtime sync.

### Step 3: Disable Email Confirmation for Mobile Auth Scheme
1. In Supabase Dashboard, navigate to **Authentication -> Providers -> Email**.
2. Turn **OFF** `Confirm email`.
3. Save changes. This enables fast 10-digit mobile number registration and login (`<mobile>@vc2026.app`).

---

## 2. Environment Variables & HTML Setup

Before deploying to Netlify, update the constants in `index.html`:

```javascript
const SUPABASE_URL = 'https://your-supabase-project-id.supabase.co';
const SUPABASE_ANON_KEY = 'your-actual-anon-publishable-key';
```

> **Note**: Never expose your Supabase `service_role` key in frontend code. Use only the publishable `anon` key.

---

## 3. Netlify Production Deployment

### Option A: Drag and Drop Deployment
1. Log into your [Netlify Account](https://app.netlify.com/).
2. Navigate to **Sites -> Add new site -> Deploy manually**.
3. Drag and drop your project directory (`vinayaka_management_v2/`) containing `index.html`.

### Option B: Git / Repository Integration
1. Push `index.html` to your GitHub/GitLab repository.
2. Link the repository in Netlify.
3. Set build settings:
   - **Publish directory**: `.` (or root directory containing `index.html`)
   - **Build command**: Leave blank (static web app)

---

## 4. Verification Checklist

After deployment, perform these tests:
- [ ] Open the live Netlify app URL over HTTPS.
- [ ] Submit a new user registration with mobile number and password.
- [ ] Log in with the registered credentials -> Verify session persists on page refresh.
- [ ] Test tab switching speed -> Ensure response is instant (<100ms).
- [ ] Upload multiple gallery images -> Verify parallel batch upload and thumbnail rendering.
- [ ] Add a donation & generate a thermal receipt -> Test printing and WhatsApp share options.
- [ ] Open two browser windows -> Verify real-time updates sync across devices automatically.
