import { IFoodProvider, FoodItem } from '../types.ts';

export class USDAProvider implements IFoodProvider {
  name = 'usda';
  private apiKey: string;

  constructor(apiKey?: string) {
    this.apiKey = apiKey || 'DEMO_KEY';
  }

  async search(query: string, page: number = 1, pageSize: number = 20): Promise<FoodItem[]> {
    if (!query || !query.trim()) return [];

    try {
      const url = `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(
        this.apiKey
      )}&query=${encodeURIComponent(query)}&pageNumber=${page}&pageSize=${pageSize}`;

      const res = await fetch(url);
      if (!res.ok) {
        console.warn(`[USDAProvider] HTTP Error ${res.status}`);
        return [];
      }

      const data = await res.json();
      if (!data || !Array.isArray(data.foods)) {
        return [];
      }

      return data.foods.map((rawFood: any): FoodItem => {
        const nutrients: Record<string, number> = {};
        if (Array.isArray(rawFood.foodNutrients)) {
          rawFood.foodNutrients.forEach((n: any) => {
            const nutrientId = String(n.nutrientId || n.nutrientNumber);
            const nameLower = (n.nutrientName || '').toLowerCase();
            const value = Number(n.value || 0);

            if (nutrientId === '1008' || nutrientId === '208' || nameLower.includes('energy')) {
              if (!nutrients.calories || n.unitName?.toLowerCase() === 'kcal') {
                nutrients.calories = value;
              }
            } else if (nutrientId === '1003' || nutrientId === '203' || nameLower.includes('protein')) {
              nutrients.protein = value;
            } else if (nutrientId === '1005' || nutrientId === '205' || nameLower.includes('carbohydrate')) {
              nutrients.carbs = value;
            } else if (nutrientId === '1004' || nutrientId === '204' || nameLower.includes('total lipid') || nameLower === 'fat') {
              nutrients.fat = value;
            } else if (nutrientId === '1079' || nutrientId === '291' || nameLower.includes('fiber')) {
              nutrients.fiber = value;
            } else if (nutrientId === '2000' || nutrientId === '269' || nameLower.includes('sugars')) {
              nutrients.sugar = value;
            } else if (nutrientId === '1093' || nutrientId === '307' || nameLower.includes('sodium')) {
              nutrients.sodium = value;
            }
          });
        }

        const providerId = String(rawFood.fdcId);
        const name = rawFood.description || 'Generic Food';
        const brand = rawFood.brandOwner || rawFood.brandName || null;
        const category = rawFood.foodCategory || rawFood.wweiaFoodCategory?.wweiaFoodCategoryDescription || 'Generic';

        return {
          id: `usda-${providerId}`,
          provider: 'usda',
          providerId,
          name,
          brand,
          description: rawFood.additionalDescriptions || rawFood.ingredients || null,
          category,
          imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&q=80&w=300',
          barcode: rawFood.gtinUpc || null,
          nutritionPer100g: {
            calories: nutrients.calories ?? 0,
            protein: nutrients.protein ?? 0,
            carbs: nutrients.carbs ?? 0,
            fat: nutrients.fat ?? 0,
            fiber: nutrients.fiber ?? null,
            sugar: nutrients.sugar ?? null,
            sodium: nutrients.sodium ?? null,
          },
          serving: {
            servingSize: Number(rawFood.servingSize || 100),
            servingUnit: rawFood.servingSizeUnit || 'g',
          },
          metadata: {
            dataType: rawFood.dataType,
            publishedDate: rawFood.publishedDate,
          },
        };
      });
    } catch (err) {
      console.error('[USDAProvider] Exception during search:', err);
      return [];
    }
  }
}
