import 'package:flutter/material.dart';

import 'app_icon.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({this.title = 'Pocket Cinema', super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AppIcon(),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFFFB4A3),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
    ],
  );
}
