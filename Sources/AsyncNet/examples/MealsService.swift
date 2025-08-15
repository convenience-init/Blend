#if canImport(UIKit)
import UIKit
#else
import Cocoa
#endif
//import AsyncNet


protocol ResponseModel {
	associatedtype MealResponse
	associatedtype RecipeResponse
	associatedtype ImageResponse
}

protocol MealResponseModel: ResponseModel where MealResponse == Models.MealResponse, RecipeResponse == Models.RecipeResponse, ImageResponse == UIImage {
	
	func getMeals(categoryName: String) async throws -> MealResponse
	func getMealDetails(mealId: String) async throws -> RecipeResponse
	@MainActor func getMealImage(url: String) async throws -> ImageResponse
}

struct MealsService: MealResponseModel, AsyncRequestable {
	typealias ResponseModel = Models.MealResponse
	typealias RecipeResponse = Models.RecipeResponse
	
	func getMeals(categoryName: String) async throws -> ResponseModel {
		
		return try await sendRequest(to: MealsEndpoint.category(categoryName: categoryName))
	}
	
	func getMealDetails(mealId: String) async throws -> RecipeResponse {
		
		return try await sendRequest(to: MealsEndpoint.recipe(mealId: mealId))
	}
	
	@MainActor func getMealImage(url: String) async throws -> ImageResponse {
		
		return try await ImageService.shared.fetchImage(from: url)
	}
}

