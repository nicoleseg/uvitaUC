import Foundation

// Curated vitamin D database — USDA FoodData Central sourced values.
// Covers the ~50 foods that meaningfully contribute dietary vitamin D.
// Values are µg per standard serving. Used as primary lookup before
// hitting any API — avoids the 0.0 problem with Open Food Facts.

struct VitaminDFood {
    let name:        String
    let category:    String
    let vitaminDug:  Double   // µg per serving
    let servingDesc: String
    let brand:       String

    // IU equivalent for display
    var vitaminDiu: Double { vitaminDug * 40 }
}

struct VitaminDFoodDatabase {

    static let foods: [VitaminDFood] = [

        // ── Fatty fish ────────────────────────────────────────
        VitaminDFood(name: "Salmon, Atlantic, farmed, cooked",
            category: "Fish", vitaminDug: 16.9,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Salmon, Atlantic, wild, cooked",
            category: "Fish", vitaminDug: 19.8,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Salmon, sockeye, cooked",
            category: "Fish", vitaminDug: 17.9,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Tuna, light, canned in water",
            category: "Fish", vitaminDug: 5.7,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Tuna, yellowfin, cooked",
            category: "Fish", vitaminDug: 6.6,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Mackerel, Atlantic, cooked",
            category: "Fish", vitaminDug: 16.1,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Sardines, canned in oil",
            category: "Fish", vitaminDug: 4.6,
            servingDesc: "2 sardines (24g)", brand: ""),
        VitaminDFood(name: "Herring, Atlantic, pickled",
            category: "Fish", vitaminDug: 2.4,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Swordfish, cooked",
            category: "Fish", vitaminDug: 14.1,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Rainbow trout, farmed, cooked",
            category: "Fish", vitaminDug: 16.2,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Halibut, cooked",
            category: "Fish", vitaminDug: 4.9,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Cod liver oil",
            category: "Oil", vitaminDug: 34.0,
            servingDesc: "1 tbsp (13.6g)", brand: ""),

        // ── Eggs ──────────────────────────────────────────────
        VitaminDFood(name: "Egg, whole, large, cooked",
            category: "Eggs", vitaminDug: 1.1,
            servingDesc: "1 large egg (50g)", brand: ""),
        VitaminDFood(name: "Egg yolk, raw",
            category: "Eggs", vitaminDug: 1.0,
            servingDesc: "1 yolk (17g)", brand: ""),
        VitaminDFood(name: "Eggs, scrambled",
            category: "Eggs", vitaminDug: 1.5,
            servingDesc: "2 eggs (100g)", brand: ""),

        // ── Fortified dairy ───────────────────────────────────
        VitaminDFood(name: "Milk, whole, vitamin D fortified",
            category: "Dairy", vitaminDug: 3.2,
            servingDesc: "1 cup (244ml)", brand: ""),
        VitaminDFood(name: "Milk, 2%, vitamin D fortified",
            category: "Dairy", vitaminDug: 3.0,
            servingDesc: "1 cup (244ml)", brand: ""),
        VitaminDFood(name: "Milk, skim, vitamin D fortified",
            category: "Dairy", vitaminDug: 2.9,
            servingDesc: "1 cup (244ml)", brand: ""),
        VitaminDFood(name: "Yogurt, plain, fortified",
            category: "Dairy", vitaminDug: 2.0,
            servingDesc: "6 oz (170g)", brand: ""),
        VitaminDFood(name: "Cheese, cheddar",
            category: "Dairy", vitaminDug: 0.3,
            servingDesc: "1 oz (28g)", brand: ""),
        VitaminDFood(name: "Butter",
            category: "Dairy", vitaminDug: 0.2,
            servingDesc: "1 tbsp (14g)", brand: ""),

        // ── Fortified plant milks ─────────────────────────────
        VitaminDFood(name: "Soy milk, fortified",
            category: "Plant milk", vitaminDug: 2.9,
            servingDesc: "1 cup (244ml)", brand: ""),
        VitaminDFood(name: "Almond milk, fortified",
            category: "Plant milk", vitaminDug: 2.4,
            servingDesc: "1 cup (244ml)", brand: ""),
        VitaminDFood(name: "Oat milk, fortified",
            category: "Plant milk", vitaminDug: 2.5,
            servingDesc: "1 cup (244ml)", brand: ""),
        VitaminDFood(name: "Rice milk, fortified",
            category: "Plant milk", vitaminDug: 2.4,
            servingDesc: "1 cup (244ml)", brand: ""),

        // ── Fortified orange juice ────────────────────────────
        VitaminDFood(name: "Orange juice, fortified with vitamin D",
            category: "Juice", vitaminDug: 2.5,
            servingDesc: "1 cup (240ml)", brand: ""),

        // ── Fortified cereals ─────────────────────────────────
        VitaminDFood(name: "Cereal, fortified (generic)",
            category: "Cereal", vitaminDug: 2.5,
            servingDesc: "1 serving (30g)", brand: ""),
        VitaminDFood(name: "Total Whole Grain cereal",
            category: "Cereal", vitaminDug: 2.5,
            servingDesc: "3/4 cup (30g)", brand: "General Mills"),
        VitaminDFood(name: "Raisin Bran",
            category: "Cereal", vitaminDug: 1.0,
            servingDesc: "1 cup (59g)", brand: "Kellogg's"),
        VitaminDFood(name: "Cheerios",
            category: "Cereal", vitaminDug: 1.3,
            servingDesc: "1 cup (28g)", brand: "General Mills"),

        // ── Mushrooms ─────────────────────────────────────────
        VitaminDFood(name: "Mushrooms, UV-exposed/treated",
            category: "Mushrooms", vitaminDug: 9.2,
            servingDesc: "1/2 cup (70g)", brand: ""),
        VitaminDFood(name: "Mushrooms, portobello, UV-exposed",
            category: "Mushrooms", vitaminDug: 7.9,
            servingDesc: "1/2 cup sliced (86g)", brand: ""),
        VitaminDFood(name: "Mushrooms, white, raw (no UV)",
            category: "Mushrooms", vitaminDug: 0.1,
            servingDesc: "1/2 cup (48g)", brand: ""),

        // ── Meat / liver ──────────────────────────────────────
        VitaminDFood(name: "Beef liver, cooked",
            category: "Meat", vitaminDug: 1.1,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Pork, cooked",
            category: "Meat", vitaminDug: 0.8,
            servingDesc: "3 oz (85g)", brand: ""),
        VitaminDFood(name: "Chicken breast, cooked",
            category: "Meat", vitaminDug: 0.1,
            servingDesc: "3 oz (85g)", brand: ""),

        // ── Supplements ───────────────────────────────────────
        VitaminDFood(name: "Vitamin D supplement, 1000 IU",
            category: "Supplement", vitaminDug: 25.0,
            servingDesc: "1 tablet", brand: ""),
        VitaminDFood(name: "Vitamin D supplement, 2000 IU",
            category: "Supplement", vitaminDug: 50.0,
            servingDesc: "1 tablet", brand: ""),
        VitaminDFood(name: "Vitamin D supplement, 5000 IU",
            category: "Supplement", vitaminDug: 125.0,
            servingDesc: "1 tablet", brand: ""),
        VitaminDFood(name: "Multivitamin with vitamin D",
            category: "Supplement", vitaminDug: 10.0,
            servingDesc: "1 tablet", brand: ""),

        // ── Fortified foods ───────────────────────────────────
        VitaminDFood(name: "Margarine, fortified",
            category: "Spreads", vitaminDug: 1.5,
            servingDesc: "1 tbsp (14g)", brand: ""),
        VitaminDFood(name: "Tofu, firm, raw",
            category: "Other", vitaminDug: 2.5,
            servingDesc: "1/2 cup (126g)", brand: ""),
    ]

    // Search by name — case insensitive, matches any word
    static func search(query: String) -> [VitaminDFood] {
        let q = query.lowercased()
            .trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        let words = q.split(separator: " ").map(String.init)

        return foods
            .filter { food in
                let haystack = (food.name + " " + food.category
                    + " " + food.brand).lowercased()
                return words.allSatisfy { haystack.contains($0) }
            }
            .sorted { a, b in
                // Exact name match first, then by vitamin D content
                let aExact = a.name.lowercased().contains(q)
                let bExact = b.name.lowercased().contains(q)
                if aExact != bExact { return aExact }
                return a.vitaminDug > b.vitaminDug
            }
    }

    // Convert to FoodItem for the existing UI
    static func searchAsFoodItems(query: String) -> [FoodItem] {
        search(query: query).map { food in
            FoodItem(
                id:          food.name,
                name:        food.name,
                brand:       food.brand,
                vitaminDug:  food.vitaminDug,
                servingDesc: food.servingDesc)
        }
    }
}
