-- ============================================================
-- PhysIQ PRO — Complete Supabase Schema Migration
-- ============================================================
-- Run this migration in Supabase SQL Editor or via CLI:
--   supabase db push
-- ============================================================

-- ============================================================
-- 1. PROFILES
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  name TEXT DEFAULT '',
  avatar_url TEXT DEFAULT '',
  goal TEXT DEFAULT 'Improve Fitness',
  gender TEXT DEFAULT 'Prefer not to say',
  age INTEGER DEFAULT 25,
  height_cm NUMERIC DEFAULT 175,
  weight_kg NUMERIC DEFAULT 70,
  target_weight_kg NUMERIC DEFAULT 70,
  activity_level TEXT DEFAULT 'Moderately Active',
  experience_level TEXT DEFAULT 'Intermediate',
  workout_location TEXT DEFAULT 'Gym',
  equipment JSONB DEFAULT '[]'::jsonb,
  workout_days_per_week INTEGER DEFAULT 4,
  workout_duration_min INTEGER DEFAULT 60,
  priority_muscles JSONB DEFAULT '[]'::jsonb,
  injuries JSONB DEFAULT '[]'::jsonb,
  diet TEXT DEFAULT 'No Preference',
  allergies JSONB DEFAULT '[]'::jsonb,
  daily_water_target_l NUMERIC DEFAULT 2.5,
  avg_sleep_hours NUMERIC DEFAULT 7.5,
  estimated_calories INTEGER DEFAULT 2000,
  protein_target_g INTEGER DEFAULT 150,
  carbs_target_g INTEGER DEFAULT 200,
  fats_target_g INTEGER DEFAULT 65,
  overall_recovery_score INTEGER DEFAULT 80,
  recommended_split TEXT DEFAULT 'Push/Pull/Legs',
  is_onboarded BOOLEAN DEFAULT false,
  body_fat_pct NUMERIC,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
  ON profiles FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Public profile fields for community (limited columns via views)
CREATE OR REPLACE VIEW public_profiles AS
SELECT id, name, avatar_url, goal, experience_level, overall_recovery_score
FROM profiles;

-- ============================================================
-- 2. AUTO-CREATE PROFILE ON SIGNUP (Trigger)
-- Fires on every new Google/Apple OAuth sign-up
-- Seeds a full profile + 9 muscle recovery records
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (
    id, email, name, avatar_url,
    goal, gender, age, height_cm, weight_kg, target_weight_kg,
    activity_level, experience_level, workout_location,
    equipment, workout_days_per_week, workout_duration_min,
    priority_muscles, injuries, diet, allergies,
    daily_water_target_l, avg_sleep_hours,
    estimated_calories, protein_target_g, carbs_target_g, fats_target_g,
    overall_recovery_score, recommended_split, is_onboarded
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Athlete'),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture', ''),
    'Improve Fitness',        -- goal
    'Prefer not to say',      -- gender
    25,                       -- age
    175,                      -- height_cm
    70.0,                     -- weight_kg
    70.0,                     -- target_weight_kg
    'Moderately Active',      -- activity_level
    'Intermediate',           -- experience_level
    'Gym',                    -- workout_location
    '["Dumbbells","Barbell","Bench","Cable Machine"]'::jsonb,
    4,                        -- workout_days_per_week
    60,                       -- workout_duration_min
    '[]'::jsonb,              -- priority_muscles
    '["None"]'::jsonb,        -- injuries
    'No Preference',          -- diet
    '["None"]'::jsonb,        -- allergies
    2.5,                      -- daily_water_target_l
    7.5,                      -- avg_sleep_hours
    2000,                     -- estimated_calories
    150,                      -- protein_target_g
    200,                      -- carbs_target_g
    65,                       -- fats_target_g
    80,                       -- overall_recovery_score
    'Push/Pull/Legs',         -- recommended_split
    false                     -- is_onboarded (will go through onboarding)
 );
-- Normalize media paths for exercises
UPDATE exercises
SET
  image_url = CASE
    WHEN image_url IS NULL THEN NULL
    WHEN image_url LIKE 'images/%' THEN image_url
    ELSE 'images/' || regexp_replace(image_url, '^.*/([^/]+)$', '\\1')
  END,
  gif_url = CASE
    WHEN gif_url IS NULL THEN NULL
    WHEN gif_url LIKE 'gifs/%' THEN gif_url
    ELSE 'gifs/' || regexp_replace(gif_url, '^.*/([^/]+)$', '\\1')
  END;

-- Normalize media paths for exercises
UPDATE exercises
SET
  image_url = CASE
    WHEN image_url IS NULL THEN NULL
    WHEN image_url LIKE 'images/%' THEN image_url
    ELSE 'images/' || regexp_replace(image_url, '^.*/([^/]+)$', '\\1')
  END,
  gif_url = CASE
    WHEN gif_url IS NULL THEN NULL
    WHEN gif_url LIKE 'gifs/%' THEN gif_url
    ELSE 'gifs/' || regexp_replace(gif_url, '^.*/([^/]+)$', '\\1')
  END;

  -- Seed baseline muscle recovery map for 3D Body Explorer
  INSERT INTO public.muscle_statuses (id, user_id, name, category, status, recovery_percentage, readiness, fatigue_level)
  VALUES
    ('chest',      NEW.id, 'Pectoralis Major',       'Chest',     'Recovered', 100, 'High', 'None'),
    ('shoulders',  NEW.id, 'Deltoids',               'Shoulders', 'Recovered', 100, 'High', 'None'),
    ('biceps',     NEW.id, 'Biceps Brachii',         'Arms',      'Recovered', 100, 'High', 'None'),
    ('triceps',    NEW.id, 'Triceps Brachii',        'Arms',      'Recovered', 100, 'High', 'None'),
    ('back',       NEW.id, 'Latissimus Dorsi',       'Back',      'Recovered', 100, 'High', 'None'),
    ('abs',        NEW.id, 'Rectus Abdominis',       'Core',      'Recovered', 100, 'High', 'None'),
    ('quads',      NEW.id, 'Quadriceps',             'Legs',      'Recovered', 100, 'High', 'None'),
    ('hamstrings', NEW.id, 'Hamstrings',             'Legs',      'Recovered', 100, 'High', 'None'),
    ('calves',     NEW.id, 'Gastrocnemius & Soleus', 'Legs',      'Recovered', 100, 'High', 'None');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 3. MUSCLE STATUSES
-- ============================================================
CREATE TABLE IF NOT EXISTS muscle_statuses (
  id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  status TEXT DEFAULT 'Inactive',
  recovery_percentage INTEGER DEFAULT 100,
  readiness TEXT DEFAULT 'High',
  fatigue_level TEXT DEFAULT 'None',
  recovery_time_hours TEXT DEFAULT 'Fully Recovered',
  training_effect TEXT DEFAULT 'Low',
  volume_kg NUMERIC DEFAULT 0,
  growth_potential TEXT DEFAULT 'Medium',
  protein_synthesis TEXT DEFAULT 'Baseline',
  blood_flow TEXT DEFAULT 'Normal',
  last_workout TEXT DEFAULT 'Never',
  next_suggested_workout TEXT DEFAULT 'Ready Anytime',
  ai_tip TEXT DEFAULT '',
  recommended_exercises JSONB DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (id, user_id)
);

ALTER TABLE muscle_statuses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own muscles"
  ON muscle_statuses FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own muscles"
  ON muscle_statuses FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own muscles"
  ON muscle_statuses FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================
-- 4. FOOD (Global food database — public read)
-- Safe migration: preserve existing data, add missing columns
-- ============================================================
CREATE TABLE IF NOT EXISTS food (
  food_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Safely append missing columns to existing food table
ALTER TABLE food ADD COLUMN IF NOT EXISTS food_id UUID DEFAULT gen_random_uuid();
ALTER TABLE food ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE food ADD COLUMN IF NOT EXISTS brand TEXT;
ALTER TABLE food ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'General';
ALTER TABLE food ADD COLUMN IF NOT EXISTS barcode TEXT;
ALTER TABLE food ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE food ADD COLUMN IF NOT EXISTS serving_size TEXT DEFAULT '100g';
ALTER TABLE food ADD COLUMN IF NOT EXISTS calories NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS protein NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS carbs NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS fat NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS fiber NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS sugar NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS sodium NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS cholesterol NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS saturated_fat NUMERIC DEFAULT 0;
ALTER TABLE food ADD COLUMN IF NOT EXISTS serving_weight NUMERIC DEFAULT 100;
ALTER TABLE food ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT false;
ALTER TABLE food ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'user';
ALTER TABLE food ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE food ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'food' AND policyname = 'Anyone can read food'
  ) THEN
    CREATE POLICY "Anyone can read food" ON food FOR SELECT USING (true);
  END IF;
END $$;

-- Keep foods table alias for backwards compatibility
CREATE TABLE IF NOT EXISTS foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  category TEXT DEFAULT 'General',
  brand TEXT,
  image_url TEXT,
  serving_size TEXT DEFAULT '100g',
  calories NUMERIC DEFAULT 0,
  protein_g NUMERIC DEFAULT 0,
  carbs_g NUMERIC DEFAULT 0,
  fat_g NUMERIC DEFAULT 0,
  fiber_g NUMERIC DEFAULT 0,
  sugar_g NUMERIC,
  sodium_mg NUMERIC,
  potassium_mg NUMERIC,
  vitamins JSONB,
  minerals JSONB,
  barcode TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE foods ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'foods' AND policyname = 'Anyone can read foods'
  ) THEN
    CREATE POLICY "Anyone can read foods" ON foods FOR SELECT USING (true);
  END IF;
END $$;

-- ============================================================
-- 5. FOOD LOGS (Per-user daily meal tracking)
-- ============================================================
CREATE TABLE IF NOT EXISTS food_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  food_id UUID REFERENCES foods(id),
  name TEXT NOT NULL,
  calories NUMERIC DEFAULT 0,
  protein_g NUMERIC DEFAULT 0,
  carbs_g NUMERIC DEFAULT 0,
  fat_g NUMERIC DEFAULT 0,
  fiber_g NUMERIC DEFAULT 0,
  sugar_g NUMERIC DEFAULT 0,
  meal_type TEXT DEFAULT 'Snack',
  image_url TEXT,
  serving_size TEXT DEFAULT '1 serving',
  servings NUMERIC DEFAULT 1,
  logged_at TIMESTAMPTZ DEFAULT now(),
  log_date DATE DEFAULT CURRENT_DATE
);

ALTER TABLE food_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own food logs"
  ON food_logs FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own food logs"
  ON food_logs FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own food logs"
  ON food_logs FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_food_logs_user_date ON food_logs(user_id, log_date);

-- ============================================================
-- 6. WATER LOGS
-- ============================================================
CREATE TABLE IF NOT EXISTS water_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount_l NUMERIC DEFAULT 0,
  log_date DATE DEFAULT CURRENT_DATE,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, log_date)
);

ALTER TABLE water_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own water logs"
  ON water_logs FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own water logs"
  ON water_logs FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own water logs"
  ON water_logs FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================
-- 7. FAVORITE FOODS
-- ============================================================
CREATE TABLE IF NOT EXISTS favorite_foods (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  food_id UUID NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, food_id)
);

ALTER TABLE favorite_foods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own favorites"
  ON favorite_foods FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 8. EXERCISES (Global exercise library — public read)
-- ============================================================
CREATE TABLE IF NOT EXISTS exercises (
  id TEXT PRIMARY KEY,
  exercise_name TEXT NOT NULL,
  muscle_group TEXT,
  target_muscles JSONB DEFAULT '[]'::jsonb,
  secondary_muscles JSONB DEFAULT '[]'::jsonb,
  equipment TEXT DEFAULT 'body weight',
  difficulty TEXT DEFAULT 'Intermediate',
  exercise_type TEXT DEFAULT 'Strength',
  movement_pattern TEXT DEFAULT 'Compound',
  instructions TEXT DEFAULT '',
  instruction_steps JSONB DEFAULT '[]'::jsonb,
  common_mistakes JSONB DEFAULT '[]'::jsonb,
  tips JSONB DEFAULT '[]'::jsonb,
  gif_url TEXT,
  image_url TEXT,
  calories INTEGER DEFAULT 0,
  sets INTEGER DEFAULT 3,
  reps TEXT DEFAULT '10-12',
  rest_time INTEGER DEFAULT 60,
  estimated_time_min INTEGER DEFAULT 5,
  physiq_muscle_keys JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;
-- Normalize media paths for exercises
UPDATE exercises
SET
  image_url = CASE
    WHEN image_url IS NULL THEN NULL
    WHEN image_url LIKE 'images/%' THEN image_url
    ELSE 'images/' || regexp_replace(image_url, '^.*/([^/]+)$', '\\1')
  END,
  gif_url = CASE
    WHEN gif_url IS NULL THEN NULL
    WHEN gif_url LIKE 'gifs/%' THEN gif_url
    ELSE 'gifs/' || regexp_replace(gif_url, '^.*/([^/]+)$', '\\1')
  END;

CREATE POLICY "Anyone can read exercises"
  ON exercises FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 9. WORKOUT PROGRAMS
-- ============================================================
CREATE TABLE IF NOT EXISTS workout_programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  subtitle TEXT DEFAULT '',
  focus_area TEXT DEFAULT '',
  duration_min INTEGER DEFAULT 60,
  exercise_count INTEGER DEFAULT 0,
  total_sets INTEGER DEFAULT 0,
  est_calories_burn INTEGER DEFAULT 0,
  readiness_percentage INTEGER DEFAULT 80,
  difficulty TEXT DEFAULT 'Intermediate',
  recovery_impact TEXT DEFAULT 'Moderate',
  ai_recommendation TEXT DEFAULT '',
  muscles_targeted JSONB DEFAULT '[]'::jsonb,
  exercises JSONB DEFAULT '[]'::jsonb,
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE workout_programs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own programs"
  ON workout_programs FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 10. WORKOUT HISTORY
-- ============================================================
CREATE TABLE IF NOT EXISTS workout_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  program_id UUID REFERENCES workout_programs(id),
  title TEXT NOT NULL,
  focus_area TEXT DEFAULT '',
  duration_min INTEGER DEFAULT 0,
  total_sets INTEGER DEFAULT 0,
  total_reps INTEGER DEFAULT 0,
  total_volume_kg NUMERIC DEFAULT 0,
  calories_burned INTEGER DEFAULT 0,
  muscles_worked JSONB DEFAULT '[]'::jsonb,
  exercises_completed JSONB DEFAULT '[]'::jsonb,
  completed_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE workout_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own workout history"
  ON workout_history FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_workout_history_user ON workout_history(user_id, completed_at DESC);

-- ============================================================
-- 11. RECOVERY LOGS
-- ============================================================
CREATE TABLE IF NOT EXISTS recovery_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  sleep_hours NUMERIC,
  sleep_quality TEXT DEFAULT 'Good',
  stress_level TEXT DEFAULT 'Low',
  heart_rate_resting INTEGER,
  heart_rate_variability INTEGER,
  readiness_score INTEGER DEFAULT 80,
  fatigue_level TEXT DEFAULT 'None',
  recovery_score INTEGER DEFAULT 80,
  notes TEXT,
  log_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, log_date)
);

ALTER TABLE recovery_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own recovery logs"
  ON recovery_logs FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 12. ANALYTICS SNAPSHOTS
-- ============================================================
CREATE TABLE IF NOT EXISTS analytics_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  period_type TEXT NOT NULL, -- 'weekly', 'monthly', 'yearly'
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  avg_calories NUMERIC,
  avg_protein_g NUMERIC,
  avg_carbs_g NUMERIC,
  avg_fat_g NUMERIC,
  total_workouts INTEGER DEFAULT 0,
  total_volume_kg NUMERIC DEFAULT 0,
  avg_recovery_score NUMERIC,
  weight_start_kg NUMERIC,
  weight_end_kg NUMERIC,
  body_fat_start NUMERIC,
  body_fat_end NUMERIC,
  data JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, period_type, period_start)
);

ALTER TABLE analytics_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own analytics"
  ON analytics_snapshots FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 13. WEIGHT HISTORY
-- ============================================================
CREATE TABLE IF NOT EXISTS weight_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  weight_kg NUMERIC NOT NULL,
  body_fat_pct NUMERIC,
  log_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, log_date)
);

ALTER TABLE weight_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own weight history"
  ON weight_history FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 14. COMMUNITY PROGRAMS
-- ============================================================
CREATE TABLE IF NOT EXISTS community_programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  cover_image TEXT DEFAULT '',
  difficulty TEXT DEFAULT 'Intermediate',
  duration_weeks INTEGER DEFAULT 4,
  workouts_per_week INTEGER DEFAULT 3,
  estimated_session_min INTEGER DEFAULT 60,
  est_calories_burn INTEGER DEFAULT 0,
  goal TEXT DEFAULT 'General Fitness',
  location TEXT DEFAULT 'Gym',
  category TEXT DEFAULT '',
  target_muscles JSONB DEFAULT '[]'::jsonb,
  equipment JSONB DEFAULT '[]'::jsonb,
  rating NUMERIC DEFAULT 0,
  downloads_count INTEGER DEFAULT 0,
  saves_count INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  tags JSONB DEFAULT '[]'::jsonb,
  weekly_schedule JSONB DEFAULT '[]'::jsonb,
  exercises JSONB DEFAULT '[]'::jsonb,
  is_published BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE community_programs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read published community programs"
  ON community_programs FOR SELECT TO authenticated USING (is_published = true OR auth.uid() = author_id);

CREATE POLICY "Authors can insert community programs"
  ON community_programs FOR INSERT WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Authors can update own community programs"
  ON community_programs FOR UPDATE USING (auth.uid() = author_id);

CREATE POLICY "Authors can delete own community programs"
  ON community_programs FOR DELETE USING (auth.uid() = author_id);

-- ============================================================
-- 15. COMMUNITY RECIPES
-- ============================================================
CREATE TABLE IF NOT EXISTS community_recipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  cover_image TEXT DEFAULT '',
  category TEXT DEFAULT '',
  calories NUMERIC DEFAULT 0,
  protein_g NUMERIC DEFAULT 0,
  carbs_g NUMERIC DEFAULT 0,
  fat_g NUMERIC DEFAULT 0,
  fiber_g NUMERIC DEFAULT 0,
  prep_time_min INTEGER DEFAULT 15,
  difficulty TEXT DEFAULT 'Easy',
  likes_count INTEGER DEFAULT 0,
  downloads_count INTEGER DEFAULT 0,
  saves_count INTEGER DEFAULT 0,
  rating NUMERIC DEFAULT 0,
  tags JSONB DEFAULT '[]'::jsonb,
  ingredients JSONB DEFAULT '[]'::jsonb,
  cooking_steps JSONB DEFAULT '[]'::jsonb,
  micronutrients JSONB DEFAULT '[]'::jsonb,
  serving_size TEXT,
  est_cost TEXT,
  meal_type_recommendation TEXT,
  is_published BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE community_recipes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read published recipes"
  ON community_recipes FOR SELECT TO authenticated USING (is_published = true OR auth.uid() = author_id);

CREATE POLICY "Authors can manage own recipes"
  ON community_recipes FOR INSERT WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Authors can update own recipes"
  ON community_recipes FOR UPDATE USING (auth.uid() = author_id);

CREATE POLICY "Authors can delete own recipes"
  ON community_recipes FOR DELETE USING (auth.uid() = author_id);

-- ============================================================
-- 16. COMMUNITY POSTS (Social Feed)
-- ============================================================
CREATE TABLE IF NOT EXISTS community_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  tab TEXT DEFAULT 'Gym', -- 'Gym' | 'Nutrition'
  category TEXT DEFAULT '',
  content TEXT NOT NULL,
  image_url TEXT,
  routine_or_recipe_badge JSONB,
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  saves_count INTEGER DEFAULT 0,
  shares_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read posts"
  ON community_posts FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authors can insert posts"
  ON community_posts FOR INSERT WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Authors can update own posts"
  ON community_posts FOR UPDATE USING (auth.uid() = author_id);

CREATE POLICY "Authors can delete own posts"
  ON community_posts FOR DELETE USING (auth.uid() = author_id);

-- ============================================================
-- 17. POST COMMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS post_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  likes_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE post_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read comments"
  ON post_comments FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert comments"
  ON post_comments FOR INSERT WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Users can update own comments"
  ON post_comments FOR UPDATE USING (auth.uid() = author_id);

CREATE POLICY "Users can delete own comments"
  ON post_comments FOR DELETE USING (auth.uid() = author_id);

-- ============================================================
-- 18. LIKES (Posts, Programs, Recipes)
-- ============================================================
CREATE TABLE IF NOT EXISTS post_likes (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

ALTER TABLE post_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own post likes"
  ON post_likes FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS post_saves (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

ALTER TABLE post_saves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own post saves"
  ON post_saves FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS program_likes (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES community_programs(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, program_id)
);

ALTER TABLE program_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own program likes"
  ON program_likes FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS program_saves (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES community_programs(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, program_id)
);

ALTER TABLE program_saves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own program saves"
  ON program_saves FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS program_downloads (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES community_programs(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, program_id)
);

ALTER TABLE program_downloads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own downloads"
  ON program_downloads FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS program_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES community_programs(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, program_id)
);

ALTER TABLE program_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read reviews"
  ON program_reviews FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can manage own reviews"
  ON program_reviews FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own reviews"
  ON program_reviews FOR UPDATE USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS recipe_likes (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipe_id UUID NOT NULL REFERENCES community_recipes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, recipe_id)
);

ALTER TABLE recipe_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own recipe likes"
  ON recipe_likes FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS recipe_saves (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipe_id UUID NOT NULL REFERENCES community_recipes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, recipe_id)
);

ALTER TABLE recipe_saves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own recipe saves"
  ON recipe_saves FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 19. FOLLOWS
-- ============================================================
CREATE TABLE IF NOT EXISTS follows (
  follower_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id != following_id)
);

ALTER TABLE follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can see follows"
  ON follows FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can manage own follows"
  ON follows FOR INSERT WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "Users can unfollow"
  ON follows FOR DELETE USING (auth.uid() = follower_id);

-- ============================================================
-- 20. CREATOR PROFILES (Extended public info)
-- ============================================================
CREATE TABLE IF NOT EXISTS creator_profiles (
  user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  display_name TEXT DEFAULT '',
  username TEXT UNIQUE,
  cover_url TEXT DEFAULT '',
  bio TEXT DEFAULT '',
  country TEXT DEFAULT '',
  flag_emoji TEXT DEFAULT '',
  join_date TEXT DEFAULT '',
  verified BOOLEAN DEFAULT false,
  role_title TEXT DEFAULT '',
  followers_count INTEGER DEFAULT 0,
  following_count INTEGER DEFAULT 0,
  programs_published INTEGER DEFAULT 0,
  total_downloads INTEGER DEFAULT 0,
  total_likes INTEGER DEFAULT 0,
  average_rating NUMERIC DEFAULT 0,
  workout_completions INTEGER DEFAULT 0,
  community_xp INTEGER DEFAULT 0,
  creator_level TEXT DEFAULT 'Level 1',
  primary_goal TEXT DEFAULT '',
  training_style TEXT DEFAULT '',
  favorite_split TEXT DEFAULT '',
  specializations JSONB DEFAULT '[]'::jsonb,
  achievements JSONB DEFAULT '[]'::jsonb,
  recent_activity JSONB DEFAULT '[]'::jsonb,
  social_links JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE creator_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read creator profiles"
  ON creator_profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can manage own creator profile"
  ON creator_profiles FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own creator profile"
  ON creator_profiles FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================
-- 21. CHALLENGES
-- ============================================================
CREATE TABLE IF NOT EXISTS challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  subtitle TEXT DEFAULT '',
  cover_image TEXT DEFAULT '',
  category TEXT DEFAULT 'Gym',
  duration_days INTEGER DEFAULT 30,
  participants_count INTEGER DEFAULT 0,
  xp_reward INTEGER DEFAULT 0,
  badge_title TEXT DEFAULT '',
  badge_color TEXT DEFAULT 'cyan',
  description TEXT DEFAULT '',
  daily_goal TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read challenges"
  ON challenges FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 22. CHALLENGE PARTICIPANTS
-- ============================================================
CREATE TABLE IF NOT EXISTS challenge_participants (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  progress_days INTEGER DEFAULT 0,
  xp_gained INTEGER DEFAULT 0,
  score TEXT DEFAULT '',
  joined_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, challenge_id)
);

ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own challenge participation"
  ON challenge_participants FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Anyone can read participation for leaderboards"
  ON challenge_participants FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 23. COACHES
-- ============================================================
CREATE TABLE IF NOT EXISTS coaches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  display_name TEXT NOT NULL,
  username TEXT,
  type TEXT DEFAULT 'Trainer',
  avatar_url TEXT DEFAULT '',
  cover_url TEXT DEFAULT '',
  role_title TEXT DEFAULT '',
  verified BOOLEAN DEFAULT false,
  location TEXT DEFAULT '',
  flag_emoji TEXT DEFAULT '',
  rating NUMERIC DEFAULT 0,
  reviews_count INTEGER DEFAULT 0,
  clients_count INTEGER DEFAULT 0,
  followers_count INTEGER DEFAULT 0,
  bio TEXT DEFAULT '',
  specializations JSONB DEFAULT '[]'::jsonb,
  hourly_rate TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE coaches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read coaches"
  ON coaches FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 24. NOTIFICATIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type TEXT NOT NULL, -- 'like', 'comment', 'follow', 'challenge', 'workout', 'recovery'
  title TEXT NOT NULL,
  body TEXT DEFAULT '',
  data JSONB DEFAULT '{}'::jsonb,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own notifications"
  ON notifications FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC);

-- ============================================================
-- 25. USER SAVED PROGRAMS (Downloaded community programs)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  source_program_id UUID REFERENCES community_programs(id),
  title TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_favorite BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_programs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own saved programs"
  ON user_programs FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 26. UPDATED_AT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_workout_programs_updated_at
  BEFORE UPDATE ON workout_programs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_community_programs_updated_at
  BEFORE UPDATE ON community_programs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_community_recipes_updated_at
  BEFORE UPDATE ON community_recipes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 27. INCREMENT/DECREMENT HELPER FUNCTIONS
-- ============================================================
CREATE OR REPLACE FUNCTION increment_count(table_name TEXT, column_name TEXT, row_id UUID, amount INTEGER DEFAULT 1)
RETURNS VOID AS $$
BEGIN
  EXECUTE format('UPDATE %I SET %I = %I + $1 WHERE id = $2', table_name, column_name, column_name)
  USING amount, row_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 28. ENABLE REALTIME
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE food_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE water_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE muscle_statuses;
ALTER PUBLICATION supabase_realtime ADD TABLE workout_history;
ALTER PUBLICATION supabase_realtime ADD TABLE recovery_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;
ALTER PUBLICATION supabase_realtime ADD TABLE post_comments;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ============================================================
-- 29. STORAGE BUCKETS (Run separately in Supabase Dashboard or via API)
-- ============================================================
-- INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('exercise-images', 'exercise-images', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('exercise-gifs', 'exercise-gifs', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('exercise-videos', 'exercise-videos', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('nutrition-images', 'nutrition-images', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('body-models', 'body-models', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('community-media', 'community-media', true);
