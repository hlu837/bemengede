// Picks the right WebIframeMap implementation at compile time:
//  - web_iframe_map_web.dart  (real iframe + postMessage bridge) on web
//  - web_iframe_map_stub.dart (no-op)                            everywhere else
//
// dart.library.html is only available in web compiles, so this never pulls
// dart:html into Android/iOS/desktop builds.
export 'web_iframe_map_stub.dart'
    if (dart.library.html) 'web_iframe_map_web.dart';
