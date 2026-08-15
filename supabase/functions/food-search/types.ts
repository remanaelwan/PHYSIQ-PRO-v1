export interface NutritionPer100g {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number | null;
  sugar: number | null;
  sodium: number | null;
}

export interface ServingInfo {
  servingSize: number;
  servingUnit: string;
}

export interface FoodItem {
  id: string;
  provider: 'usda' | 'openfoodfacts' | 'database' | string;
  providerId: string;
  name: string;
  brand: string | null;
  description: string | null;
  category: string | null;
  imageUrl: string | null;
  barcode: string | null;
  nutritionPer100g: NutritionPer100g;
  serving: ServingInfo;
  metadata?: Record<string, any>;
  createdAt?: string;
  updatedAt?: string;
}

export interface SearchFoodsRequest {
  query?: string;
  barcode?: string;
  page?: number;
  pageSize?: number;
}

export interface SearchFoodsResponse {
  success: boolean;
  foods: FoodItem[];
  pagination: {
    page: number;
    pageSize: number;
    hasMore: boolean;
  };
  error?: string;
}

export interface IFoodProvider {
  name: string;
  search(query: string, page: number, pageSize: number): Promise<FoodItem[]>;
  getByBarcode?(barcode: string): Promise<FoodItem | null>;
}
