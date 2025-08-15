import Foundation

typealias IngredientName = String
typealias IngredientMeasure = String
typealias RecipeStep = String

//Namespace for Models
enum Models {
	enum MealType: String, CaseIterable {
		case desserts = "Dessert"
	}
}

extension Models {
	struct MealResponse: Decodable, Hashable {
		var meals: [Meal] = []
	}
}

extension Models {
	struct Meal: Decodable, Hashable {
		var id: String = ""
		var name: String = ""
		var imageURL: String = ""
	}
}

// Recipe AKA MealDetails
extension Models {
	struct RecipeResponse: Decodable, Hashable {
		var recipes: [Recipe] = []
	}
}

extension Models {
	struct Recipe: Decodable, Hashable {
		var id: String = ""
		var name: String = ""
		var category: String = ""
		var imageURL: String = ""
		var ingredients: [Ingredient] = []
		var steps: [RecipeStep] = []
	}
}

extension Models {
	struct Ingredient: Codable, Hashable {
		
		var name: IngredientName = ""
		var measure: IngredientMeasure = ""
		var imageURL: String {
			return "https://www.themealdb.com/images/ingredients/\(name).png"
		}
	}
}

extension Models.Recipe {
	
	init(from decoder: Decoder) throws {
		
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let nameContainer = try decoder.container(keyedBy: IngredientNameCodingKeys.self)
		let measureContainer = try decoder.container(keyedBy: IngredientMeasureCodingKeys.self)
		let instructionsContainer = try decoder.container(keyedBy: InstructionsStepsCodingKeys.self)
		
		id = try container.decode(String.self, forKey: .id)
		name = try container.decode(String.self, forKey: .name)
		category = try container.decode(String.self, forKey: .category)
		imageURL = try container.decode(String.self, forKey: .imageURL)
		
		let instructions = try instructionsContainer.decodeIfPresent(RecipeStep.self, forKey: .instructions)
		if let instructions {
            steps = instructions.components(separatedBy: "\n").compactMap { step in
                let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
		}
		
		let nameKeys = IngredientNameCodingKeys.allCases
		let measureKeys = IngredientMeasureCodingKeys.allCases
		
		for (nameKey, measureKey) in zip(nameKeys, measureKeys) {
			let name = try nameContainer.decodeIfPresent(String.self, forKey: nameKey)
			let measure = try measureContainer.decodeIfPresent(String.self, forKey: measureKey)
			
			if let name = name, let measure = measure,
			   name.isNotEmpty() && measure.isNotEmpty() {
				let ingredient = Models.Ingredient(name: name, measure: measure)
				ingredients.append(ingredient)
			}
		}
	}
}

extension Models.Meal {
	enum CodingKeys: String, CodingKey {
		case id = "idMeal",
			 name = "strMeal",
			 imageURL = "strMealThumb"
	}
}

extension Models.RecipeResponse {
	enum CodingKeys: String, CodingKey {
		case recipes = "meals"
	}
}

extension Models.Recipe {
	enum CodingKeys: String, CodingKey {
		case id = "idMeal",
			 name = "strMeal",
			 category = "strCategory",
			 imageURL = "strMealThumb",
			 steps
	}
	
	enum InstructionsStepsCodingKeys: String, CodingKey {
		case instructions = "strInstructions"
	}
	
	enum IngredientNameCodingKeys: String, CodingKey, CaseIterable {
		case strIngredient1, strIngredient2, strIngredient3, strIngredient4, strIngredient5, strIngredient6, strIngredient7, strIngredient8, strIngredient9, strIngredient10, strIngredient11, strIngredient12, strIngredient13, strIngredient14, strIngredient15, strIngredient16, strIngredient17, strIngredient18, strIngredient19, strIngredient20
	}
	
	enum IngredientMeasureCodingKeys: String, CodingKey, CaseIterable {
		case strMeasure1, strMeasure2, strMeasure3, strMeasure4, strMeasure5, strMeasure6, strMeasure7, strMeasure8, strMeasure9, strMeasure10, strMeasure11, strMeasure12, strMeasure13, strMeasure14, strMeasure15, strMeasure16, strMeasure17, strMeasure18, strMeasure19, strMeasure20
	}
}

fileprivate extension String {
	func isNotEmpty() -> Bool {
		!self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
	func isEmpty() -> Bool {
		self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}


