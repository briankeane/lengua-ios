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
      getVocabItems: { targetLanguageCode, limit, cursor in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken, !token.isEmpty else {
          throw APIError.unauthorized
        }

        let url = baseUrl.appendingPathComponent("v1/vocab-items")
        var parameters: [String: Any] = ["limit": limit ?? 50]
        if let targetLanguageCode { parameters["targetLanguageCode"] = targetLanguageCode }
        if let cursor { parameters["cursor"] = cursor }

        let response = await session.request(
          url,
          parameters: parameters,
          encoding: URLEncoding.default,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let httpResponse = response.response,
          (200..<300).contains(httpResponse.statusCode),
          let data = response.data
        else { throw APIError.dataNotValid }

        guard
          let decoded = try? JSONDecoder.lenguaISO8601.decode(
            VocabItemsResponse.self, from: data)
        else { throw APIError.dataNotValid }

        return VocabItemsPage(
          items: decoded.vocabItems, nextCursor: decoded.pagination.nextCursor)
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
          let item = try? JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: data)
        else { throw APIError.dataNotValid }

        return item
      },
      deleteVocabItem: { id in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken, !token.isEmpty else {
          throw APIError.unauthorized
        }

        let url =
          baseUrl
          .appendingPathComponent("v1/vocab-items")
          .appendingPathComponent(id)
        let response = await session.request(
          url,
          method: .delete,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let httpResponse = response.response else {
          throw response.error ?? APIError.dataNotValid
        }

        // 204 = deleted, 404 = already gone or not owned. Both are the same end
        // state for the client, so treat 404 as success (mirrors save's 200/201).
        if httpResponse.statusCode == 204 || httpResponse.statusCode == 404 {
          return
        }
        if httpResponse.statusCode == 401 { throw APIError.unauthorized }
        throw APIError.dataNotValid
      },
      getReviewQueue: { direction, limit, targetLanguageCode in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken, !token.isEmpty else { throw APIError.unauthorized }

        let url = baseUrl.appendingPathComponent("v1/vocab-items/review")
        var parameters: [String: Any] = ["limit": limit ?? 20]
        if let direction { parameters["direction"] = direction.rawValue }
        if let targetLanguageCode { parameters["targetLanguageCode"] = targetLanguageCode }

        let response = await session.request(
          url, parameters: parameters, encoding: URLEncoding.default,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let http = response.response, let data = response.data else {
          throw APIError.dataNotValid
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.dataNotValid }
        guard
          let decoded = try? JSONDecoder.lenguaISO8601.decode(ReviewQueueResponse.self, from: data)
        else { throw APIError.dataNotValid }
        return ReviewQueue(cards: decoded.reviewCards, dueCounts: decoded.dueCounts)
      },
      submitReview: { vocabItemId, direction, outcome in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken, !token.isEmpty else { throw APIError.unauthorized }

        let url = baseUrl.appendingPathComponent("v1/vocab-items/\(vocabItemId)/review")
        let response = await session.request(
          url, method: .post,
          parameters: ["direction": direction.rawValue, "outcome": outcome.rawValue],
          encoding: JSONEncoding.default,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let http = response.response else { throw response.error ?? APIError.dataNotValid }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode), let data = response.data else {
          let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
          throw APIError.validationError(body ?? "Review failed (\(http.statusCode))")
        }
        guard let item = try? JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: data)
        else { throw APIError.dataNotValid }
        return item
      }
    )
  }()
}
