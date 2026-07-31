import CustomDump
import Foundation
import Testing

@testable import Lengua

@MainActor
struct SignInErrorReportTests {
  @Test func redactsNonJSONResponseBody() {
    let error = SignInAPIError(
      authMethod: .google,
      endpointPath: "/v1/auth/google",
      statusCode: 500,
      responseBody: "<html>Internal Server Error: token=secret</html>",
      underlyingError: APIError.dataNotValid)

    let report = SignInErrorReport(error: error, authMethod: .google, step: "api_call")

    expectNoDifference(report.context["response_body"], "[REDACTED NON-JSON RESPONSE]")
    #expect(report.context["response_body"]?.contains("secret") != true)
  }

  @Test func redactsTokenFieldsInJSONResponseBody() {
    let error = SignInAPIError(
      authMethod: .google,
      endpointPath: "/v1/auth/google",
      statusCode: 200,
      responseBody: #"{"token":"secret-jwt","message":"unexpected shape"}"#,
      underlyingError: APIError.dataNotValid)

    let report = SignInErrorReport(error: error, authMethod: .google, step: "api_call")

    #expect(report.context["response_body"]?.contains("secret-jwt") != true)
    #expect(report.context["response_body"]?.contains("[REDACTED]") == true)
    #expect(report.context["response_body"]?.contains("unexpected shape") == true)
  }
}
