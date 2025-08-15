import Foundation
//import AsyncNet

enum MealsEndpoint {
	case categories
	case category(categoryName: String)
	case recipe(mealId: String)
}

extension MealsEndpoint: Endpoint {
	
	var scheme: URLScheme {
		return .https
	}

	var host: String {
		switch self {
			case .categories, .category, .recipe:
				return "themealdb.com"
		}
	}
	
	var queryItems: [URLQueryItem]? {
		switch self {
			case .categories:
				return [URLQueryItem(name: "c", value: "list")]
				
			case .category(let categoryName):
				return [URLQueryItem(name: "c", value: "\(categoryName.capitalized)")]
				
			case .recipe(let mealId):
				return [URLQueryItem(name: "i", value: "\(mealId)")]
		}
	}
	
	var path: String {
		switch self {
			case .categories:
				return "/api/json/v1/1/list.php"
			case .category:
				return "/api/json/v1/1/filter.php"
			case .recipe:
				return "/api/json/v1/1/lookup.php"
		}
	}
	
	var method: RequestMethod {
		switch self {
			case .categories, .category, .recipe:
				return .get
		}
	}
	
	var header: [String: String]? {
		return ["Content-Type": "application/json;charset=utf-8"]
	}
	
	var body: [String: String]? {
		switch self {
			case .categories, .category, .recipe:
				return nil
		}
	}
}

