{{flutter_js}}
{{flutter_build_config}}

// index.html pins <base href="/"> (CSP base-uri 'self'); these keep every
// Flutter resource at / as well, for deep URLs such as /w or /regalo/x.
_flutter.loader.load({
  config: {
    entrypointBaseUrl: '/',
    assetBase: '/',
    canvasKitBaseUrl: '/canvaskit/',
    fontFallbackBaseUrl: '/assets/fonts/',
  },
});
