{{flutter_js}}
{{flutter_build_config}}

// This entry point is a development preview, so always request current code.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += `?preview=${Date.now()}`;
}
_flutter.loader.load();
