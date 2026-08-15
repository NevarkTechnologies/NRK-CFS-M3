// Non-web stub, selected when dart.library.io is available (mobile/desktop).
// Mobile uses the custom button + imperative signIn(), so the GIS button is
// never shown there; this returns an empty widget to satisfy the shared API.
import 'package:flutter/widgets.dart';

Widget renderGoogleSignInButton() => const SizedBox.shrink();
