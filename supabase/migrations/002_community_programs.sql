-- ============================================================
-- PhysIQ PRO — Community Programs Schema Migration
-- ============================================================

-- 1. COMMUNITY CREATORS
CREATE TABLE IF NOT EXISTS community_creators (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  bio TEXT DEFAULT '',
  verified_badge BOOLEAN DEFAULT false,
  social_links JSONB DEFAULT '[]'::jsonb,
  rating NUMERIC DEFAULT 0.0,
  followers_count INTEGER DEFAULT 0,
  programs_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE community_creators ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read community_creators" ON community_creators FOR SELECT USING (true);
CREATE POLICY "Users update own creator profile" ON community_creators FOR UPDATE USING (auth.uid() = id);

-- 2. COMMUNITY PROGRAMS
-- Note: Recreating or altering to ensure all required fields are present.
CREATE TABLE IF NOT EXISTS community_programs_v2 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  creator_id UUID REFERENCES community_creators(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  goal TEXT,
  difficulty TEXT DEFAULT 'Intermediate',
  exercise_count INTEGER DEFAULT 0,
  estimated_duration INTEGER DEFAULT 0,
  cover_image TEXT,
  tags JSONB DEFAULT '[]'::jsonb,
  exercises JSONB NOT NULL DEFAULT '[]'::jsonb,
  weekly_schedule JSONB DEFAULT '[]'::jsonb,
  required_equipment JSONB DEFAULT '[]'::jsonb,
  muscles_trained JSONB DEFAULT '[]'::jsonb,
  is_published BOOLEAN DEFAULT false,
  is_approved BOOLEAN DEFAULT false,
  downloads_count INTEGER DEFAULT 0,
  rating NUMERIC DEFAULT 0.0,
  likes_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE community_programs_v2 ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read approved community_programs_v2" ON community_programs_v2 FOR SELECT USING (is_published = true AND is_approved = true OR auth.uid() = author_id);
CREATE POLICY "Users insert own community_programs_v2" ON community_programs_v2 FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "Users update own community_programs_v2" ON community_programs_v2 FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "Users delete own community_programs_v2" ON community_programs_v2 FOR DELETE USING (auth.uid() = author_id);

-- 3. COMMUNITY REVIEWS
CREATE TABLE IF NOT EXISTS community_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id UUID NOT NULL REFERENCES community_programs_v2(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE community_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read community_reviews" ON community_reviews FOR SELECT USING (true);
CREATE POLICY "Users manage own reviews" ON community_reviews FOR ALL USING (auth.uid() = user_id);

-- 4. COMMUNITY LIKES
CREATE TABLE IF NOT EXISTS community_likes_v2 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id UUID NOT NULL REFERENCES community_programs_v2(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(program_id, user_id)
);
ALTER TABLE community_likes_v2 ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read community_likes_v2" ON community_likes_v2 FOR SELECT USING (true);
CREATE POLICY "Users manage own likes" ON community_likes_v2 FOR ALL USING (auth.uid() = user_id);

-- 5. COMMUNITY DOWNLOADS (IMPORTS)
CREATE TABLE IF NOT EXISTS community_downloads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id UUID NOT NULL REFERENCES community_programs_v2(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  imported_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE community_downloads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read community_downloads" ON community_downloads FOR SELECT USING (true);
CREATE POLICY "Users manage own downloads" ON community_downloads FOR ALL USING (auth.uid() = user_id);

-- 6. TRIGGERS for Updated_At
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_community_creators_updated_at
BEFORE UPDATE ON community_creators FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_community_programs_v2_updated_at
BEFORE UPDATE ON community_programs_v2 FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
