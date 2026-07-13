// Web implementation of WebIframeMap: embeds web/gebeta_iframe_map.html
// (real MapLibre GL JS, confirmed working directly in the browser) via an
// iframe, and bridges postMessage events so Dart can react to taps and push
// marker updates without recreating the iframe.

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:gebeta_gl/gebeta_gl.dart' show LatLng;
import '../../services/gebeta_service.dart';

int _viewTypeCounter = 0;

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
  State<WebIframeMap> createState() => _WebIframeMapWebState();
}

class _WebIframeMapWebState extends State<WebIframeMap> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  StreamSubscription<html.Event>? _messageSub;
  bool _iframeLoaded = false;
  bool _mapReady = false;
  bool _initSent = false;

  @override
  void initState() {
    super.initState();

    _viewType = 'gebeta-iframe-map-${_viewTypeCounter++}';

    _iframe = html.IFrameElement()
      ..src = 'gebeta_iframe_map.html'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';

    _iframe.onLoad.first.then((_) {
      _iframeLoaded = true;
      _maybeSendInit();
    });

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _iframe,
    );

    _messageSub = html.window.onMessage.listen(_handleMessage);
  }

  void _handleMessage(html.Event event) {
    final msgEvent = event as html.MessageEvent;
    final data = msgEvent.data;
    if (data is! Map) return;

    final type = data['type'];
    switch (type) {
      case 'gebeta:ready':
        _mapReady = true;
        _maybeSendInit();
        break;
      case 'gebeta:click':
        if (widget.onTap != null) {
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            widget.onTap!(LatLng(lat, lng));
          }
        }
        break;
      case 'gebeta:error':
        // ignore: avoid_print
        print('Gebeta iframe map error: ${data['message']}');
        break;
    }
  }

  void _maybeSendInit() {
    if (!_iframeLoaded || !_mapReady || _initSent) return;
    _initSent = true;
    _postToIframe({
      'type': 'gebeta:init',
      'apiKey': GebetaService.apiKey,
      'styleUrl': GebetaService.styleUrl,
      'lat': widget.initial.latitude,
      'lng': widget.initial.longitude,
      'zoom': widget.zoom,
      'interactive': widget.interactive,
    });
    if (widget.markerAt != null) {
      _postToIframe({
        'type': 'gebeta:setMarker',
        'lat': widget.markerAt!.latitude,
        'lng': widget.markerAt!.longitude,
      });
    }
  }

  void _postToIframe(Map<String, dynamic> payload) {
    _iframe.contentWindow?.postMessage(payload, '*');
  }

  @override
  void didUpdateWidget(covariant WebIframeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initSent) return;

    final oldMarker = oldWidget.markerAt;
    final newMarker = widget.markerAt;
    if (newMarker != oldMarker) {
      if (newMarker == null) {
        _postToIframe({'type': 'gebeta:clearMarker'});
      } else {
        _postToIframe({
          'type': 'gebeta:setMarker',
          'lat': newMarker.latitude,
          'lng': newMarker.longitude,
        });
        _postToIframe({
          'type': 'gebeta:animateTo',
          'lat': newMarker.latitude,
          'lng': newMarker.longitude,
        });
      }
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
