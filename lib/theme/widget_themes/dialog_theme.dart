import 'package:flutter/material.dart';
import '../../utils/constants/colors.dart';

/* -- Light & Dark Elevated Button Themes -- */
class AppDialogTheme {
  AppDialogTheme._(); //To avoid creating instances


  /* -- Light Theme -- */
  static const lightDialogTheme  = DialogThemeData(
   backgroundColor: AppColors.white,
    surfaceTintColor: Colors.transparent
  );

  /* -- Dark Theme -- */
  static const darkDialogTheme = DialogThemeData(

    );
}
