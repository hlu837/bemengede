// Non-web stub for WebIframeMap. Never actually built — map_screen.dart
// only reaches for WebIframeMap when kIsWeb is true — but this file must
// still exist and compile on Android/iOS/desktop, since the conditional
// import in web_iframe_map.dart picks one of these two files unconditionally
// at compile time for every platform.

import 'package:flutter/material.dart';
import 'package:gebeta_gl/gebeta_gl.dart' show LatLng;

class WebIframeMap extends StatefulWidget {
  final LatLng initial;
  final double zoom;
  final bool interactive;
  final LatLng? markerAt;
  final void Function(LatLng)? onTap;

  const WebIframeMap({
    super.key,
    required this.initial,
    this.zoom = 13,
    this.interactive = true,
    this.markerAt,
    this.onTap,
  });

  @override
  State<WebIframeMap> createState() => _WebIframeMapStubState();
}

class _WebIframeMapStubState extends State<WebIframeMap> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
