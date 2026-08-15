// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import { FoodItem, SearchFoodsRequest, SearchFoodsResponse } from './types.ts';
import { USDAProvider } from './providers/USDAProvider.ts';
import { OpenFoodFactsProvider } from './providers/OpenFoodFactsProvider.ts';

// Common Arabic to English translation dictionary for fitness/food search
const ARABIC_FOOD_MAP: Record<string, string> = {
  'فراخ': 'chicken',
  'دجاج': 'chicken',
  'صدر فراخ': 'chicken breast',
  'صدور دجاج': 'chicken breast',
  'أرز': 'rice',
  'رز': 'rice',
  'بيض': 'eggs',
  'بيضة': 'egg',
  'تونة': 'tuna',
  'لحمة': 'beef',
  'لحم': 'beef',
  'سمك': 'fish',
  'زبادي': 'yogurt',
  'حليب': 'milk',
  'لبن': 'milk',
  'جبنة': 'cheese',
  'تفاح': 'apple',
  'موز': 'banana',
  'شوفان': 'oats',
  'بطاطس': 'potato',
  'بطاطا': 'sweet potato',
  'زيت زيتون': 'olive oil',
  'بروتين': 'protein',
  'سالمون': 'salmon',
  'جمبري': 'shrimp',
};

export function normalizeQuery(query: string): string {
  let q = query.trim().toLowerCase();
  for (const [ar, en] of Object.entries(ARABIC_FOOD_MAP)) {
    if (q.includes(ar)) {
      q = q.replace(ar, en);
    }
  }
  return q;
}

export function deduplicateFoods(foods: FoodItem[]): FoodItem[] {
  const seen = new Set<string>();
  const results: FoodItem[] = [];

  for (const item of foods) {
    const key = item.barcode
      ? `barcode:${item.barcode}`
      : `name:${item.name.trim().toLowerCase()}|brand:${(item.brand || '').trim().toLowerCase()}`;

    if (!seen.has(key)) {
      seen.add(key);
      results.push(item);
    }
  }

  return results;
}

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || '';
    const usdaApiKey = Deno.env.get('USDA_API_KEY') || '';

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body: SearchFoodsRequest = await req.json().catch(() => ({}));
    const query = body.query?.trim() || '';
    const barcode = body.barcode?.trim() || '';
    const page = Math.max(1, body.page || 1);
    const pageSize = Math.min(50, Math.max(1, body.pageSize || 20));

    const usda = new USDAProvider(usdaApiKey);
    const openFoodFacts = new OpenFoodFactsProvider();

    // 1. Handle Barcode Lookup directly
    if (barcode) {
      const offResult = await openFoodFacts.getByBarcode(barcode);
      if (offResult) {
        return new Response(
          JSON.stringify({
            success: true,
            foods: [offResult],
            pagination: { page: 1, pageSize: 1, hasMore: false },
          } as SearchFoodsResponse),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    if (!query || query.length < 2) {
      return new Response(
        JSON.stringify({
          success: true,
          foods: [],
          pagination: { page, pageSize, hasMore: false },
        } as SearchFoodsResponse),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const searchStr = normalizeQuery(query);

    // 2. Fetch results concurrently from USDA & OpenFoodFacts
    const [usdaResults, offResults] = await Promise.all([
      usda.search(searchStr, page, pageSize),
      openFoodFacts.search(searchStr, page, pageSize),
    ]);

    const combined = [...usdaResults, ...offResults];
    const deduplicated = deduplicateFoods(combined);
    const paginated = deduplicated.slice(0, pageSize);
    const hasMore = deduplicated.length > pageSize;

    // 3. Cache results asynchronously into Supabase `foods` table
    if (paginated.length > 0 && supabaseUrl) {
      const rowsToInsert = paginated.map((f) => ({
        provider: f.provider,
        provider_food_id: f.providerId,
        name: f.name,
        brand: f.brand,
        description: f.description,
        category: f.category,
        image_url: f.imageUrl,
        barcode: f.barcode,
        calories_per_100g: f.nutritionPer100g.calories,
        protein_per_100g: f.nutritionPer100g.protein,
        carbs_per_100g: f.nutritionPer100g.carbs,
        fat_per_100g: f.nutritionPer100g.fat,
        fiber_per_100g: f.nutritionPer100g.fiber,
        sugar_per_100g: f.nutritionPer100g.sugar,
        sodium_per_100g: f.nutritionPer100g.sodium,
        serving_size: f.serving.servingSize,
        serving_unit: f.serving.servingUnit,
        metadata: f.metadata || {},
      }));

      supabase
        .from('foods')
        .upsert(rowsToInsert, { onConflict: 'provider,provider_food_id' })
        .then(({ error }) => {
          if (error) console.error('[EdgeFunction] Food cache error:', error.message);
        });
    }

    const response: SearchFoodsResponse = {
      success: true,
      foods: paginated,
      pagination: {
        page,
        pageSize,
        hasMore,
      },
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err: any) {
    console.error('[EdgeFunction] Server error:', err);
    return new Response(
      JSON.stringify({
        success: false,
        foods: [],
        pagination: { page: 1, pageSize: 20, hasMore: false },
        error: err?.message || 'Internal Server Error',
      } as SearchFoodsResponse),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
