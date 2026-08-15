// Web-only implementation, selected by the conditional import in login_page.dart
// (default branch; the stub is used wherever dart.library.io is available).
//
// Renders Google's official Identity Services (GIS) sign-in button. A click
// produces a CredentialResponse (carrying an idToken) that google_sign_in
// surfaces via GoogleSignIn.onCurrentUserChanged — the reliable way to obtain
// an idToken on the web (the imperative signIn() cannot).
import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

Widget renderGoogleSignInButton() => web.renderButton();
