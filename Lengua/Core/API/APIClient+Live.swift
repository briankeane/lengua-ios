import Alamofire
import Dependencies
import Foundation

extension APIClient: DependencyKey {
  static let liveValue: APIClient = {
    let session = Session()
    let baseUrl = Config.shared.baseUrl

    return APIClient(
      getAppVersionRequirements: {
        let url = baseUrl.appendingPathComponent("v1/app-version-requirements")
        let data = try await session.request(url).serializingData().value
        guard let requirements = try? JSONDecoder().decode(AppVersionRequirements.self, from: data)
        else { throw APIError.dataNotValid }
        return requirements
      },
      health: {
        let url = baseUrl.appendingPathComponent("health")
        let response = await session.request(url).serializingData().response
        return response.response?.statusCode == 200
      }
    )
  }()
}
