import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

matrix.MatrixException exception(String errcode, String error) =>
    matrix.MatrixException.fromJson({"errcode": errcode, "error": error});

void main() {
  test("M_FORBIDDEN means a wrong username or password", () {
    var result =
        loginResultForException(exception("M_FORBIDDEN", "Invalid password"));
    expect(result, isA<LoginResultInvalidCredentials>());
  });

  test("M_USER_DEACTIVATED says the account is deactivated", () {
    var result = loginResultForException(
        exception("M_USER_DEACTIVATED", "This account has been deactivated"));
    expect(result, isA<LoginResultError>());
    expect((result as LoginResultError).errorMessage, messageUserDeactivated);
  });

  test("Other errors show the server's message", () {
    var result =
        loginResultForException(exception("M_LIMIT_EXCEEDED", "Too many"));
    expect(result, isA<LoginResultError>());
    expect((result as LoginResultError).errorMessage, "Too many");
  });
}
