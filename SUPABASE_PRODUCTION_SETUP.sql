-- ============================================================
-- SRI GOWRI PUTRA YOUTH — VINAYAKA CHAVITHI MANAGEMENT SYSTEM
-- Production Database Setup & RLS Security Migration Script
-- ============================================================

-- Enable required UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------
-- 1. PROFILES / USERS TABLE
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    uid UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    mobile VARCHAR(15) UNIQUE NOT NULL,
    email VARCHAR(255),
    name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'people', -- 'people', 'admin', 'super'
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- 'pending', 'approved', 'rejected', 'revoked'
    approved BOOLEAN DEFAULT FALSE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    approved_at TIMESTAMPTZ,
    approved_by VARCHAR(255)
);

-- Index for fast user lookup by mobile and status
CREATE INDEX IF NOT EXISTS idx_user_profiles_mobile ON public.user_profiles(mobile);
CREATE INDEX IF NOT EXISTS idx_user_profiles_status ON public.user_profiles(status);

-- ------------------------------------------------------------
-- 2. CORE SYNC DATA TABLE (Key-Value Storage Fallback / Legacy Sync)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.v2_data (
    key VARCHAR(255) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 3. NORMALIZED ENTITY TABLES
-- ------------------------------------------------------------

-- DONATIONS TABLE
CREATE TABLE IF NOT EXISTS public.donations (
    id VARCHAR(100) PRIMARY KEY,
    donor VARCHAR(255) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    mode VARCHAR(50) NOT NULL DEFAULT 'Cash', -- 'Cash', 'UPI'
    status VARCHAR(50) NOT NULL DEFAULT 'Complete', -- 'Complete', 'Pending'
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    collector VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_donations_date ON public.donations(date);
CREATE INDEX IF NOT EXISTS idx_donations_status ON public.donations(status);
CREATE INDEX IF NOT EXISTS idx_donations_collector ON public.donations(collector);

-- EXPENSES TABLE
CREATE TABLE IF NOT EXISTS public.expenses (
    id VARCHAR(100) PRIMARY KEY,
    description TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    recorded_by VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses(date);

-- COMMITTEE MEMBERS TABLE
CREATE TABLE IF NOT EXISTS public.committee_members (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    role VARCHAR(100) NOT NULL DEFAULT 'Committee Member',
    avatar TEXT,
    added_by VARCHAR(255),
    added_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- SPONSORS TABLE
CREATE TABLE IF NOT EXISTS public.sponsors (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    contact VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- PRASADAM DISTRIBUTION TABLE
CREATE TABLE IF NOT EXISTS public.prasadam (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    mobile VARCHAR(20) NOT NULL,
    food_item TEXT NOT NULL,
    date DATE NOT NULL,
    session VARCHAR(50) NOT NULL CHECK (session IN ('Morning', 'Evening')),
    recorded_by VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prasadam_date_session ON public.prasadam(date, session);

-- EVENTS TABLE
CREATE TABLE IF NOT EXISTS public.events (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    session VARCHAR(50) NOT NULL CHECK (session IN ('Morning', 'Evening')),
    recorded_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_date ON public.events(date);

-- GALLERY MEDIA TABLE (Individual Photo Metadata & Storage References)
CREATE TABLE IF NOT EXISTS public.v2_gallery_photos (
    id VARCHAR(255) PRIMARY KEY,
    data_url TEXT,
    storage_path TEXT,
    title VARCHAR(255),
    uploaded_by VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- AUDIT LOGS TABLE
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_identity VARCHAR(255) NOT NULL,
    action_message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);

-- ------------------------------------------------------------
-- 4. RPC FUNCTIONS FOR REGISTRATION & PROFILE MANAGEMENT
-- ------------------------------------------------------------

-- Function to register a new profile (Self-Service Registration)
CREATE OR REPLACE FUNCTION public.register_my_profile(
    p_name TEXT,
    p_mobile TEXT,
    p_requested_role TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_user_email TEXT;
    v_existing_count INT;
    v_initial_status TEXT;
    v_initial_approved BOOLEAN;
    v_final_role TEXT;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to register profile';
    END IF;

    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;

    -- Check if any approved user exists in system
    SELECT COUNT(*) INTO v_existing_count FROM public.user_profiles WHERE status = 'approved';

    -- First account ever registered automatically becomes Super Admin!
    IF v_existing_count = 0 THEN
        v_initial_status := 'approved';
        v_initial_approved := TRUE;
        v_final_role := 'super';
    ELSE
        v_initial_status := 'pending';
        v_initial_approved := FALSE;
        v_final_role := CASE WHEN p_requested_role = 'admin' THEN 'admin' ELSE 'people' END;
    END IF;

    INSERT INTO public.user_profiles (
        uid, mobile, email, name, role, status, approved, created_at, updated_at
    ) VALUES (
        v_user_id, p_mobile, v_user_email, p_name, v_final_role, v_initial_status, v_initial_approved, NOW(), NOW()
    )
    ON CONFLICT (mobile) DO UPDATE SET
        uid = v_user_id,
        email = v_user_email,
        name = p_name,
        updated_at = NOW()
    RETURNING jsonb_build_object(
        'id', id,
        'mobile', mobile,
        'name', name,
        'role', role,
        'status', status,
        'approved', approved
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Function to fetch my authenticated profile by mobile number
CREATE OR REPLACE FUNCTION public.get_my_profile_by_mobile(
    p_mobile TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', id,
        'uid', uid,
        'mobile', mobile,
        'name', name,
        'role', role,
        'status', status,
        'approved', approved
    ) INTO v_result
    FROM public.user_profiles
    WHERE mobile = p_mobile AND (uid = auth.uid() OR status = 'approved');

    RETURN v_result;
END;
$$;

-- ------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.v2_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.committee_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sponsors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prasadam ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.v2_gallery_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Helper policy functions for role check
CREATE OR REPLACE FUNCTION public.is_approved_user()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
    WHERE uid = auth.uid() AND status = 'approved' AND approved = TRUE
  );
$$;

-- RLS: user_profiles
CREATE POLICY "Users can view approved profiles or their own profile"
    ON public.user_profiles FOR SELECT
    USING (status = 'approved' OR uid = auth.uid() OR is_approved_user());

CREATE POLICY "Users can insert their own profile"
    ON public.user_profiles FOR INSERT
    WITH CHECK (uid = auth.uid());

CREATE POLICY "Super admins can update profiles"
    ON public.user_profiles FOR UPDATE
    USING (is_approved_user());

-- RLS: v2_data
CREATE POLICY "Approved users can read v2_data"
    ON public.v2_data FOR SELECT
    USING (is_approved_user());

CREATE POLICY "Approved users can insert/update v2_data"
    ON public.v2_data FOR ALL
    USING (is_approved_user())
    WITH CHECK (is_approved_user());

-- RLS: normalized tables (read for approved users, write for approved admins)
CREATE POLICY "Approved users read donations" ON public.donations FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write donations" ON public.donations FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read expenses" ON public.expenses FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write expenses" ON public.expenses FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read committee" ON public.committee_members FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write committee" ON public.committee_members FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read sponsors" ON public.sponsors FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write sponsors" ON public.sponsors FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read prasadam" ON public.prasadam FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write prasadam" ON public.prasadam FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read events" ON public.events FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write events" ON public.events FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read gallery" ON public.v2_gallery_photos FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write gallery" ON public.v2_gallery_photos FOR ALL USING (is_approved_user());

CREATE POLICY "Approved users read logs" ON public.audit_logs FOR SELECT USING (is_approved_user());
CREATE POLICY "Approved users write logs" ON public.audit_logs FOR ALL USING (is_approved_user());

-- ------------------------------------------------------------
-- 6. ENABLE REALTIME PUBLICATIONS
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'v2_data'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.v2_data;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'v2_gallery_photos'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.v2_gallery_photos;
  END IF;
END $$;
