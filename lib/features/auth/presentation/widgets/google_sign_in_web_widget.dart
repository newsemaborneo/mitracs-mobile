import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gis;

Widget buildGoogleSignInButton() {
  return Center(
    child: SizedBox(
      height: 48,
      child: web_gis.renderButton(
        configuration: web_gis.GSIButtonConfiguration(
          theme: web_gis.GSIButtonTheme.outline,
          size: web_gis.GSIButtonSize.large,
          text: web_gis.GSIButtonText.signinWith,
          shape: web_gis.GSIButtonShape.pill,
          logoAlignment: web_gis.GSIButtonLogoAlignment.left,
        ),
      ),
    ),
  );
}
