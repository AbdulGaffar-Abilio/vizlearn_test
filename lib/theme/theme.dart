import 'package:flutter/material.dart';
import 'package:hologram_test/theme/widget_themes/appbar_theme.dart';
import 'package:hologram_test/theme/widget_themes/bottom_sheet_theme.dart';
import 'package:hologram_test/theme/widget_themes/checkbox_theme.dart';
import 'package:hologram_test/theme/widget_themes/chip_theme.dart';
import 'package:hologram_test/theme/widget_themes/dialog_theme.dart';
import 'package:hologram_test/theme/widget_themes/elevated_button_theme.dart';
import 'package:hologram_test/theme/widget_themes/outlined_button_theme.dart';
import 'package:hologram_test/theme/widget_themes/progress_bar_theme.dart';
import 'package:hologram_test/theme/widget_themes/text_field_theme.dart';
import 'package:hologram_test/theme/widget_themes/text_selection_theme.dart';
import 'package:hologram_test/theme/widget_themes/text_theme.dart';

import '../utils/constants/colors.dart';

class IAppTheme {
  IAppTheme._();

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Montserrat',
    colorScheme: ColorScheme.fromSwatch(primarySwatch: AppColors().createMaterialColor(AppColors.primary)).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.white,
      error: AppColors.red,
    ),

    disabledColor: AppColors.buttonDisabled,
    brightness: Brightness.light,
    dialogBackgroundColor: AppColors.white,
    progressIndicatorTheme: AppProgressBarTheme.lightProgressIndicatorTheme,
    primaryColor: AppColors.primary,
    textTheme: AppTextTheme.lightTextTheme,
    chipTheme: AppChipTheme.lightChipTheme,
    scaffoldBackgroundColor: AppColors.background1,
    appBarTheme: CustomAppBarTheme.lightAppBarTheme,
    checkboxTheme: AppCheckboxTheme.lightCheckboxTheme,
    bottomSheetTheme: AppBottomSheetTheme.lightBottomSheetTheme,
    elevatedButtonTheme: AppElevatedButtonTheme.lightElevatedButtonTheme,
    outlinedButtonTheme: AppOutlinedButtonTheme.lightOutlinedButtonTheme,
    inputDecorationTheme: AppTextFormFieldTheme.lightInputDecorationTheme,
    textSelectionTheme: AppTextSelection.lightTextSelectionTheme,
    dialogTheme: AppDialogTheme.lightDialogTheme,
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Montserrat',
    disabledColor: AppColors.grey,
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    textTheme: AppTextTheme.darkTextTheme,
    chipTheme: AppChipTheme.darkChipTheme,
    scaffoldBackgroundColor: AppColors.black,
    appBarTheme: CustomAppBarTheme.darkAppBarTheme,
    checkboxTheme: AppCheckboxTheme.darkCheckboxTheme,
    bottomSheetTheme: AppBottomSheetTheme.darkBottomSheetTheme,
    elevatedButtonTheme: AppElevatedButtonTheme.darkElevatedButtonTheme,
    outlinedButtonTheme: AppOutlinedButtonTheme.darkOutlinedButtonTheme,
    inputDecorationTheme: AppTextFormFieldTheme.darkInputDecorationTheme,
  );
}

ThemeData get theme => IAppTheme.lightTheme;
