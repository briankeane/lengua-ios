import Alamofire
import Dependencies
import Foundation
import Sharing

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
      },
      signInViaGoogle: { idToken in
        let path = "v1/auth/google"
        let url = baseUrl.appendingPathComponent(path)
        let response = await session.request(
          url,
          method: .post,
          parameters: ["idToken": idToken],
          encoding: JSONEncoding.default
        ).serializingData().response

        guard let httpResponse = response.response else {
          throw SignInAPIError(
            authMethod: .google, endpointPath: "/\(path)", statusCode: nil,
            responseBody: nil, underlyingError: response.error ?? APIError.dataNotValid)
        }

        let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
        guard (200..<300).contains(httpResponse.statusCode) else {
          throw SignInAPIError(
            authMethod: .google, endpointPath: "/\(path)",
            statusCode: httpResponse.statusCode, responseBody: body,
            underlyingError: response.error ?? APIError.dataNotValid)
        }

        guard let data = response.data,
          let decoded = try? JSONDecoder().decode(GoogleSignInResponse.self, from: data)
        else {
          throw SignInAPIError(
            authMethod: .google, endpointPath: "/\(path)",
            statusCode: httpResponse.statusCode, responseBody: body,
            underlyingError: APIError.dataNotValid)
        }

        return decoded.result
      },
      saveVocabItem: { request in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken, !token.isEmpty else {
          throw APIError.unauthorized
        }

        let url = baseUrl.appendingPathComponent("v1/vocab-items")
        let response = await session.request(
          url,
          method: .post,
          parameters: request,
          encoder: JSONParameterEncoder.default,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let httpResponse = response.response else {
          throw response.error ?? APIError.dataNotValid
        }

        if httpResponse.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(httpResponse.statusCode) else {
          let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
          throw APIError.validationError(body ?? "Save failed (\(httpResponse.statusCode))")
        }

        guard let data = response.data,
          let item = try? JSONDecoder().decode(VocabItem.self, from: data)
        else { throw APIError.dataNotValid }

        return item
      }
    )
  }()
}
