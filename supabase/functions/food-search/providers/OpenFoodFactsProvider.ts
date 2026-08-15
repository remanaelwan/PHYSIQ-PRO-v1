import { IFoodProvider, FoodItem } from '../types.ts';

export class OpenFoodFactsProvider implements IFoodProvider {
  name = 'openfoodfacts';

  async search(query: string, page: number = 1, pageSize: number = 20): Promise<FoodItem[]> {
    if (!query || !query.trim()) return [];

    try {
      const url = `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(
        query
      )}&search_simple=1&action=process&json=1&page=${page}&page_size=${pageSize}`;

      const res = await fetch(url, {
        headers: {
          'User-Agent': 'PhysIQ-NutritionApp/1.0 (contact@physiq.app)',
        },
      });

      if (!res.ok) {
        console.warn(`[OpenFoodFactsProvider] HTTP Error ${res.status}`);
        return [];
      }

      const data = await res.json();
      if (!data || !Array.isArray(data.products)) {
        return [];
      }

      return data.products
        .filter((p: any) => p.product_name || p.product_name_en)
        .map((raw: any) => this.mapProductToFoodItem(raw));
    } catch (err) {
      console.error('[OpenFoodFactsProvider] Exception during search:', err);
      return [];
    }
  }

  async getByBarcode(barcode: string): Promise<FoodItem | null> {
    if (!barcode || !barcode.trim()) return null;

    try {
      const url = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(barcode.trim())}.json`;
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'PhysIQ-NutritionApp/1.0 (contact@physiq.app)',
        },
      });

      if (!res.ok) return null;

      const data = await res.json();
      if (!data || data.status !== 1 || !data.product) {
        return null;
      }

      return this.mapProductToFoodItem(data.product);
    } catch (err) {
      console.error('[OpenFoodFactsProvider] Exception during barcode lookup:', err);
      return null;
    }
  }

  private mapProductToFoodItem(raw: any): FoodItem {
    const nutriments = raw.nutriments || {};
    const providerId = String(raw.id || raw.code || raw._id || Math.random());
    const name = raw.product_name_en || raw.product_name || raw.product_name_ar || 'Packaged Product';
    const brand = raw.brands || raw.brand_owner || null;
    const category = raw.categories ? raw.categories.split(',')[0]?.trim() : 'Packaged Foods';

    const calories = Number(
      nutriments['energy-kcal_100g'] ??
        nutriments['energy-kcal_value'] ??
        (nutriments['energy_100g'] ? nutriments['energy_100g'] / 4.184 : 0)
    );
    const protein = Number(nutriments['proteins_100g'] ?? nutriments['proteins_value'] ?? 0);
    const carbs = Number(nutriments['carbohydrates_100g'] ?? nutriments['carbohydrates_value'] ?? 0);
    const fat = Number(nutriments['fat_100g'] ?? nutriments['fat_value'] ?? 0);
    const fiber = nutriments['fiber_100g'] !== undefined ? Number(nutriments['fiber_100g']) : null;
    const sugar = nutriments['sugars_100g'] !== undefined ? Number(nutriments['sugars_100g']) : null;
    const sodium = nutriments['sodium_100g'] !== undefined ? Number(nutriments['sodium_100g']) * 1000 : null;

    return {
      id: `off-${providerId}`,
      provider: 'openfoodfacts',
      providerId,
      name,
      brand,
      description: raw.generic_name || raw.ingredients_text || null,
      category,
      imageUrl: raw.image_front_small_url || raw.image_front_url || raw.image_url || null,
      barcode: raw.code || null,
      nutritionPer100g: {
        calories: isNaN(calories) ? 0 : calories,
        protein: isNaN(protein) ? 0 : protein,
        carbs: isNaN(carbs) ? 0 : carbs,
        fat: isNaN(fat) ? 0 : fat,
        fiber: isNaN(fiber as number) ? null : fiber,
        sugar: isNaN(sugar as number) ? null : sugar,
        sodium: isNaN(sodium as number) ? null : sodium,
      },
      serving: {
        servingSize: Number(raw.serving_quantity || 100),
        servingUnit: raw.serving_size ? (raw.serving_size.includes('g') ? 'g' : 'ml') : 'g',
      },
      metadata: {
        nutriscore: raw.nutriscore_grade,
        ecoscore: raw.ecoscore_grade,
        novaGroup: raw.nova_group,
      },
    };
  }
}
