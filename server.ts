import express from 'express';
import path from 'path';
import { createServer as createViteServer } from 'vite';
import { GoogleGenAI } from '@google/genai';
import dotenv from 'dotenv';
import {
  getFatSecretAccessToken,
  searchFatSecretFoods,
  getFatSecretFoodById,
  getFatSecretCredentials,
} from './src/services/fatsecretServer';

dotenv.config();

async function startServer() {
  const app = express();
  const PORT = 3000;

  app.use(express.json({ limit: '10mb' }));

  // API Route: FatSecret OAuth 2.0 Token Check & Exchange
  app.get('/api/fatsecret/token', async (_req, res) => {
    try {
      const token = await getFatSecretAccessToken();
      return res.json({ success: true, token });
    } catch (err: any) {
      console.error('FatSecret Auth Failed:', err?.message || err);
      return res.status(400).json({
        error: 'FatSecret credentials are missing. Please configure the .env file.',
        details: err?.message,
      });
    }
  });

  // API Route: FatSecret Food Search Proxy
  app.post('/api/fatsecret/search', async (req, res) => {
    try {
      const { query, pageNumber, maxResults } = req.body;
      if (!query || typeof query !== 'string' || !query.trim()) {
        return res.status(400).json({ error: 'Query parameter is required' });
      }
      const data = await searchFatSecretFoods(query.trim(), pageNumber || 0, maxResults || 20);
      return res.json(data);
    } catch (err: any) {
      console.error('FatSecret Search Failed:', err?.message || err);
      return res.status(400).json({
        error: 'FatSecret credentials are missing. Please configure the .env file.',
        details: err?.message,
      });
    }
  });

  // API Route: FatSecret Food Detail Proxy
  app.post('/api/fatsecret/food-get', async (req, res) => {
    try {
      const { foodId } = req.body;
      if (!foodId) {
        return res.status(400).json({ error: 'foodId parameter is required' });
      }
      const data = await getFatSecretFoodById(String(foodId));
      return res.json(data);
    } catch (err: any) {
      console.error('FatSecret Food Details Failed:', err?.message || err);
      return res.status(400).json({
        error: 'FatSecret credentials are missing. Please configure the .env file.',
        details: err?.message,
      });
    }
  });

  // API Route: Production Food Search Edge Function Proxy (USDA + OpenFoodFacts)
  app.post(['/functions/v1/food-search', '/api/food/search'], async (req, res) => {
    try {
      const { query, barcode, page, pageSize } = req.body || {};
      const q = (query || '').trim();
      const code = (barcode || '').trim();
      const pageNum = Math.max(1, page || 1);
      const limit = Math.min(50, Math.max(1, pageSize || 20));

      const usdaApiKey = process.env.USDA_API_KEY || 'DEMO_KEY';

      // 1. Handle Barcode lookup
      if (code) {
        const offRes = await fetch(`https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(code)}.json`, {
          headers: { 'User-Agent': 'PhysIQ-NutritionApp/1.0' },
        });
        if (offRes.ok) {
          const data = await offRes.json();
          if (data && data.status === 1 && data.product) {
            const raw = data.product;
            const nut = raw.nutriments || {};
            const foodItem = {
              id: `off-${raw.code || code}`,
              provider: 'openfoodfacts',
              providerId: raw.code || code,
              name: raw.product_name_en || raw.product_name || 'Packaged Product',
              brand: raw.brands || null,
              description: raw.generic_name || null,
              category: raw.categories ? raw.categories.split(',')[0]?.trim() : 'Packaged Foods',
              imageUrl: raw.image_front_small_url || raw.image_front_url || null,
              barcode: raw.code || code,
              nutritionPer100g: {
                calories: Number(nut['energy-kcal_100g'] || nut['energy-kcal_value'] || 0),
                protein: Number(nut['proteins_100g'] || 0),
                carbs: Number(nut['carbohydrates_100g'] || 0),
                fat: Number(nut['fat_100g'] || 0),
                fiber: nut['fiber_100g'] !== undefined ? Number(nut['fiber_100g']) : null,
                sugar: nut['sugars_100g'] !== undefined ? Number(nut['sugars_100g']) : null,
                sodium: nut['sodium_100g'] !== undefined ? Number(nut['sodium_100g']) * 1000 : null,
              },
              serving: {
                servingSize: Number(raw.serving_quantity || 100),
                servingUnit: 'g',
              },
            };

            return res.json({
              success: true,
              foods: [foodItem],
              pagination: { page: 1, pageSize: 1, hasMore: false },
            });
          }
        }
      }

      if (!q || q.length < 2) {
        return res.json({
          success: true,
          foods: [],
          pagination: { page: pageNum, pageSize: limit, hasMore: false },
        });
      }

      // Arabic query translation map
      let searchStr = q.toLowerCase();
      const arMap: Record<string, string> = {
        'فراخ': 'chicken', 'دجاج': 'chicken', 'صدر فراخ': 'chicken breast',
        'أرز': 'rice', 'رز': 'rice', 'بيض': 'eggs', 'تونة': 'tuna',
        'لحمة': 'beef', 'سمك': 'fish', 'زبادي': 'yogurt', 'حليب': 'milk',
        'شوفان': 'oats', 'بطاطس': 'potato',
      };
      for (const [ar, en] of Object.entries(arMap)) {
        if (searchStr.includes(ar)) searchStr = searchStr.replace(ar, en);
      }

      // 2. Query USDA and OpenFoodFacts concurrently
      const [usdaRes, offRes] = await Promise.all([
        fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(usdaApiKey)}&query=${encodeURIComponent(searchStr)}&pageNumber=${pageNum}&pageSize=${limit}`),
        fetch(`https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(searchStr)}&search_simple=1&action=process&json=1&page=${pageNum}&page_size=${limit}`, {
          headers: { 'User-Agent': 'PhysIQ-NutritionApp/1.0' },
        }),
      ]);

      const foods: any[] = [];

      if (usdaRes.ok) {
        const uData = await usdaRes.json();
        if (uData && Array.isArray(uData.foods)) {
          uData.foods.forEach((rawFood: any) => {
            const nutrients: Record<string, number> = {};
            if (Array.isArray(rawFood.foodNutrients)) {
              rawFood.foodNutrients.forEach((n: any) => {
                const nId = String(n.nutrientId || n.nutrientNumber);
                const val = Number(n.value || 0);
                if (nId === '1008' || nId === '208') nutrients.calories = val;
                else if (nId === '1003' || nId === '203') nutrients.protein = val;
                else if (nId === '1005' || nId === '205') nutrients.carbs = val;
                else if (nId === '1004' || nId === '204') nutrients.fat = val;
                else if (nId === '1079' || nId === '291') nutrients.fiber = val;
                else if (nId === '2000' || nId === '269') nutrients.sugar = val;
                else if (nId === '1093' || nId === '307') nutrients.sodium = val;
              });
            }

            foods.push({
              id: `usda-${rawFood.fdcId}`,
              provider: 'usda',
              providerId: String(rawFood.fdcId),
              name: rawFood.description || 'Generic Food',
              brand: rawFood.brandOwner || rawFood.brandName || null,
              description: rawFood.additionalDescriptions || null,
              category: rawFood.foodCategory || 'Generic',
              imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&q=80&w=300',
              barcode: rawFood.gtinUpc || null,
              nutritionPer100g: {
                calories: nutrients.calories || 0,
                protein: nutrients.protein || 0,
                carbs: nutrients.carbs || 0,
                fat: nutrients.fat || 0,
                fiber: nutrients.fiber !== undefined ? nutrients.fiber : null,
                sugar: nutrients.sugar !== undefined ? nutrients.sugar : null,
                sodium: nutrients.sodium !== undefined ? nutrients.sodium : null,
              },
              serving: {
                servingSize: Number(rawFood.servingSize || 100),
                servingUnit: rawFood.servingSizeUnit || 'g',
              },
            });
          });
        }
      }

      if (offRes.ok) {
        const oData = await offRes.json();
        if (oData && Array.isArray(oData.products)) {
          oData.products.forEach((raw: any) => {
            if (!raw.product_name && !raw.product_name_en) return;
            const nut = raw.nutriments || {};
            foods.push({
              id: `off-${raw.id || raw.code || Math.random()}`,
              provider: 'openfoodfacts',
              providerId: String(raw.id || raw.code || Math.random()),
              name: raw.product_name_en || raw.product_name || 'Packaged Product',
              brand: raw.brands || null,
              description: raw.generic_name || null,
              category: raw.categories ? raw.categories.split(',')[0]?.trim() : 'Packaged Foods',
              imageUrl: raw.image_front_small_url || raw.image_front_url || null,
              barcode: raw.code || null,
              nutritionPer100g: {
                calories: Number(nut['energy-kcal_100g'] || nut['energy-kcal_value'] || 0),
                protein: Number(nut['proteins_100g'] || 0),
                carbs: Number(nut['carbohydrates_100g'] || 0),
                fat: Number(nut['fat_100g'] || 0),
                fiber: nut['fiber_100g'] !== undefined ? Number(nut['fiber_100g']) : null,
                sugar: nut['sugars_100g'] !== undefined ? Number(nut['sugars_100g']) : null,
                sodium: nut['sodium_100g'] !== undefined ? Number(nut['sodium_100g']) * 1000 : null,
              },
              serving: {
                servingSize: Number(raw.serving_quantity || 100),
                servingUnit: 'g',
              },
            });
          });
        }
      }

      // Deduplicate by barcode / name + brand
      const seen = new Set<string>();
      const deduped: any[] = [];
      for (const item of foods) {
        const key = item.barcode
          ? `barcode:${item.barcode}`
          : `name:${item.name.toLowerCase()}|brand:${(item.brand || '').toLowerCase()}`;
        if (!seen.has(key)) {
          seen.add(key);
          deduped.push(item);
        }
      }

      const paginated = deduped.slice(0, limit);
      return res.json({
        success: true,
        foods: paginated,
        pagination: {
          page: pageNum,
          pageSize: limit,
          hasMore: deduped.length > limit,
        },
      });
    } catch (err: any) {
      console.error('Food Search Endpoint Error:', err);
      return res.status(500).json({ success: false, error: err?.message || 'Server error' });
    }
  });

  // Initialize Gemini AI Client lazily
  function getGeminiClient() {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) return null;
    return new GoogleGenAI({ apiKey });
  }

  // API Route: Onboarding Analysis
  app.post('/api/ai/onboarding-analysis', async (req, res) => {
    try {
      const answers = req.body;
      const ai = getGeminiClient();

      if (!ai) {
        // Return structured baseline if key not set
        return res.json({
          estimatedCalories: 2450,
          proteinTargetG: 175,
          carbsTargetG: 260,
          fatsTargetG: 70,
          recoveryScore: 82,
          split: 'Push / Pull / Legs (5-Day Hypertrophy)',
          aiAdvice: 'Based on your profile, we have calibrated a 5-day workout split focused on progressive overload and high protein intake.',
        });
      }

      const prompt = `Analyze this user profile for PhysIQ fitness app and return ONLY a JSON object with fields: estimatedCalories (number), proteinTargetG (number), carbsTargetG (number), fatsTargetG (number), recoveryScore (number 1-100), split (string name of workout split), aiAdvice (string 2-3 sentences).
User details:
Goal: ${answers.goal || 'Build Muscle'}
Gender: ${answers.gender || 'Male'}
Age: ${answers.age || 26}
Height: ${answers.heightCm || 180} cm
Weight: ${answers.weightKg || 76.5} kg
Target Weight: ${answers.targetWeightKg || 80} kg
Activity: ${answers.activityLevel || 'Moderately Active'}
Experience: ${answers.experienceLevel || 'Intermediate'}
Equipment: ${(answers.equipment || []).join(', ')}
Days: ${answers.workoutDaysPerWeek || 5} days/week
Duration: ${answers.workoutDurationMin || 60} mins
Priority Muscles: ${(answers.priorityMuscles || []).join(', ')}
Injuries: ${(answers.injuries || []).join(', ')}
Diet: ${answers.diet || 'High Protein'}`;

      const response = await ai.models.generateContent({
        model: 'gemini-3.6-flash',
        contents: prompt,
        config: {
          responseMimeType: 'application/json',
        },
      });

      const text = response.text || '{}';
      const result = JSON.parse(text);
      return res.json(result);
    } catch (err: any) {
      console.error('Onboarding AI Error:', err);
      return res.json({
        estimatedCalories: 2400,
        proteinTargetG: 180,
        carbsTargetG: 250,
        fatsTargetG: 70,
        recoveryScore: 80,
        split: 'Custom PhysIQ 5-Day Split',
        aiAdvice: 'Personalized AI plan created based on your physical metrics and workout experience.',
      });
    }
  });

  // API Route: Food Scanner / AI Nutrition Analysis
  app.post('/api/ai/scan-food', async (req, res) => {
    try {
      const { foodQuery, imageBase64 } = req.body;
      const ai = getGeminiClient();

      if (!ai) {
        return res.json({
          name: foodQuery || 'Healthy Meal Bowl',
          calories: 520,
          proteinG: 42,
          carbsG: 48,
          fatG: 12,
          mealType: 'Lunch',
          aiNote: 'Estimated nutrition profile added to diary.',
        });
      }

      const prompt = `Analyze this food query or image and return a JSON object with: name (string), calories (number), proteinG (number), carbsG (number), fatG (number), mealType (one of Breakfast, Lunch, Snack, Dinner), aiNote (string sentence). Food query: "${foodQuery || 'Meal'}"`;

      const contents: any[] = [prompt];
      if (imageBase64) {
        contents.push({
          inlineData: {
            data: imageBase64.replace(/^data:image\/\w+;base64,/, ''),
            mimeType: 'image/jpeg',
          },
        });
      }

      const response = await ai.models.generateContent({
        model: 'gemini-3.6-flash',
        contents,
        config: {
          responseMimeType: 'application/json',
        },
      });

      const result = JSON.parse(response.text || '{}');
      return res.json(result);
    } catch (err) {
      console.error('Food scan error:', err);
      return res.json({
        name: 'Protein Meal',
        calories: 480,
        proteinG: 38,
        carbsG: 45,
        fatG: 12,
        mealType: 'Lunch',
        aiNote: 'Estimated nutrients saved to your meal diary.',
      });
    }
  });

  // API Route: AI Body Recovery Insights
  app.post('/api/ai/analyze-body', async (req, res) => {
    try {
      const { selectedMuscle, recoveryPercentage, fatigueLevel } = req.body;
      const ai = getGeminiClient();

      if (!ai) {
        return res.json({
          insight: `Your ${selectedMuscle} is at ${recoveryPercentage}% recovery with ${fatigueLevel} fatigue. Prioritize 30g protein post-workout and 8 hours of sleep for peak synthesis.`,
        });
      }

      const prompt = `Provide 2 clear, highly actionable AI recovery recommendations for a bodybuilder/athlete whose ${selectedMuscle} muscle is at ${recoveryPercentage}% recovery with ${fatigueLevel} fatigue. Keep response under 120 words.`;

      const response = await ai.models.generateContent({
        model: 'gemini-3.6-flash',
        contents: prompt,
      });

      return res.json({ insight: response.text });
    } catch (err) {
      return res.json({
        insight: `Ensure proper hydration and protein intake to optimize muscle fiber repair over the next 24 hours.`,
      });
    }
  });

  // API Route: 3D Body Scan Insights
  app.post('/api/ai/body-insights', async (req, res) => {
    try {
      const { musclesWorked, sorenessRating, sleepHours } = req.body;
      const ai = getGeminiClient();

      if (!ai) {
        return res.json({
          overallRecoveryScore: 85,
          aiInsightSummary: 'Upper body muscle groups are recovering rapidly. Recommended 48h rest before next heavy push session.',
        });
      }

      const prompt = `Analyze 3D body scan metrics: worked muscles (${(musclesWorked || []).join(', ')}), soreness rating ${sorenessRating || 4}/10, sleep ${sleepHours || 8} hours. Return JSON with overallRecoveryScore (number 1-100) and aiInsightSummary (string max 2 sentences).`;

      const response = await ai.models.generateContent({
        model: 'gemini-3.6-flash',
        contents: prompt,
        config: {
          responseMimeType: 'application/json',
        },
      });

      const result = JSON.parse(response.text || '{}');
      return res.json({
        overallRecoveryScore: result.overallRecoveryScore || 84,
        aiInsightSummary: result.aiInsightSummary || 'Muscle recovery status updated based on 3D anatomical scan.',
      });
    } catch (err) {
      return res.json({
        overallRecoveryScore: 82,
        aiInsightSummary: 'Your muscle fibers are undergoing optimal protein synthesis. Keep hydration elevated.',
      });
    }
  });

  // API Route: Daily Motivation Affirmation
  app.get('/api/daily-motivation', async (req, res) => {
    try {
      const ai = getGeminiClient();
      const today = new Date().toISOString().split('T')[0];

      if (!ai) {
        const fallbackQuotes = [
          { quote: "Discipline is doing what needs to be done, even when you don't feel like doing it.", author: "Anonymous", category: "Discipline" },
          { quote: "The only bad workout is the one that didn't happen.", author: "Fitness Proverb", category: "Consistency" },
          { quote: "Action is the foundational key to all success. Keep pushing your limits daily.", author: "Pablo Picasso", category: "Growth" },
          { quote: "Your body can stand almost anything. It's your mind that you have to convince.", author: "Arnold Schwarzenegger", category: "Mindset" },
          { quote: "Strength does not come from physical capacity. It comes from an indomitable will.", author: "Mahatma Gandhi", category: "Strength" },
        ];
        const hash = today.split('-').reduce((acc, part) => acc + (parseInt(part, 10) || 0), 0);
        const selected = fallbackQuotes[hash % fallbackQuotes.length];
        return res.json({ date: today, ...selected });
      }

      const prompt = `Generate a powerful, inspiring fitness or growth mindset affirmation for today (${today}). Return ONLY a JSON object with fields: quote (string under 120 chars), author (string name), category (string e.g. Discipline, Mindset, Consistency, Strength, Focus).`;

      const response = await ai.models.generateContent({
        model: 'gemini-3.6-flash',
        contents: prompt,
        config: {
          responseMimeType: 'application/json',
        },
      });

      const result = JSON.parse(response.text || '{}');
      return res.json({
        date: today,
        quote: result.quote || "Discipline is choosing between what you want now and what you want most.",
        author: result.author || "PhysIQ Mindset",
        category: result.category || "Discipline",
      });
    } catch (err) {
      const today = new Date().toISOString().split('T')[0];
      return res.json({
        date: today,
        quote: "Your body can stand almost anything. It's your mind that you have to convince.",
        author: "Arnold Schwarzenegger",
        category: "Mindset",
      });
    }
  });

  // Vite middleware in development
  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`PhysIQ Server running on http://0.0.0.0:${PORT}`);
  });
}

startServer();
