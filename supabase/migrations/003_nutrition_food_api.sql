-- Migration 003: Production-Ready Nutrition Food API & Meal Tracking Schema

-- Enable pgcrypto extension for UUID generation if not enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- --------------------------------------------------
-- 1. foods table (cached normalized food items)
-- --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.foods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,
    provider_food_id TEXT NOT NULL,
    name TEXT NOT NULL,
    brand TEXT,
    description TEXT,
    category TEXT,
    image_url TEXT,
    barcode TEXT,
    calories_per_100g NUMERIC(10,2) NOT NULL DEFAULT 0,
    protein_per_100g NUMERIC(10,2) NOT NULL DEFAULT 0,
    carbs_per_100g NUMERIC(10,2) NOT NULL DEFAULT 0,
    fat_per_100g NUMERIC(10,2) NOT NULL DEFAULT 0,
    fiber_per_100g NUMERIC(10,2) DEFAULT 0,
    sugar_per_100g NUMERIC(10,2) DEFAULT 0,
    sodium_per_100g NUMERIC(10,2) DEFAULT 0,
    serving_size NUMERIC(10,2) DEFAULT 100,
    serving_unit TEXT DEFAULT 'g',
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_provider_food_id UNIQUE (provider, provider_food_id)
);

-- Index for searching foods
CREATE INDEX IF NOT EXISTS idx_foods_name ON public.foods USING gin (to_tsvector('english', name));
CREATE INDEX IF NOT EXISTS idx_foods_barcode ON public.foods (barcode);
CREATE INDEX IF NOT EXISTS idx_foods_category ON public.foods (category);

-- Enable RLS on foods
ALTER TABLE public.foods ENABLE ROW LEVEL SECURITY;

-- Foods policies: Authenticated users can view cached foods; service role or logged in users can insert cached foods
CREATE POLICY "Authenticated users can select foods"
    ON public.foods FOR SELECT
    TO authenticated, anon
    USING (true);

CREATE POLICY "Authenticated users can insert cached foods"
    ON public.foods FOR INSERT
    TO authenticated, anon
    WITH CHECK (true);

-- --------------------------------------------------
-- 2. meal_logs table
-- --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meal_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    food_id UUID REFERENCES public.foods(id) ON DELETE SET NULL,
    meal_type TEXT NOT NULL CHECK (meal_type IN ('Breakfast', 'Lunch', 'Dinner', 'Snack', 'Pre-workout', 'Post-workout')),
    amount NUMERIC(10,2) NOT NULL DEFAULT 100,
    unit TEXT NOT NULL DEFAULT 'g',
    calories NUMERIC(10,2) NOT NULL DEFAULT 0,
    protein NUMERIC(10,2) NOT NULL DEFAULT 0,
    carbs NUMERIC(10,2) NOT NULL DEFAULT 0,
    fat NUMERIC(10,2) NOT NULL DEFAULT 0,
    fiber NUMERIC(10,2) DEFAULT 0,
    sugar NUMERIC(10,2) DEFAULT 0,
    sodium NUMERIC(10,2) DEFAULT 0,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    log_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for meal logs
CREATE INDEX IF NOT EXISTS idx_meal_logs_user_date ON public.meal_logs (user_id, log_date);
CREATE INDEX IF NOT EXISTS idx_meal_logs_user_logged ON public.meal_logs (user_id, logged_at DESC);

-- Enable RLS on meal_logs
ALTER TABLE public.meal_logs ENABLE ROW LEVEL SECURITY;

-- RLS policies for meal_logs: strictly own records
CREATE POLICY "Users can view own meal logs"
    ON public.meal_logs FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own meal logs"
    ON public.meal_logs FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own meal logs"
    ON public.meal_logs FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own meal logs"
    ON public.meal_logs FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- --------------------------------------------------
-- 3. meal_templates table
-- --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meal_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.meal_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own meal templates"
    ON public.meal_templates FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- --------------------------------------------------
-- 4. meal_template_items table
-- --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meal_template_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meal_template_id UUID REFERENCES public.meal_templates(id) ON DELETE CASCADE,
    food_id UUID REFERENCES public.foods(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL DEFAULT 100,
    unit TEXT NOT NULL DEFAULT 'g',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.meal_template_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own meal template items"
    ON public.meal_template_items FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.meal_templates mt
            WHERE mt.id = meal_template_items.meal_template_id
            AND mt.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.meal_templates mt
            WHERE mt.id = meal_template_items.meal_template_id
            AND mt.user_id = auth.uid()
        )
    );
