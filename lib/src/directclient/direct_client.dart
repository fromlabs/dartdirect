part of dartdirect.client;

// TODO come intercettiamo la close?

Future initializeClientDirectHandling(DirectModule module) async {
  await Chain.capture(() => capturedInitializeClientDirectHandling(module),
      onError: (e, s) => _libraryLogger.severe("Uncaught error", e, s));
}

Future capturedInitializeClientDirectHandling(DirectModule module) async {
  DIRECT_ENVIRONMENT = context["DIRECT_ENVIRONMENT"];

  Registry.load(module);

  await Registry.openScope(Scope.ISOLATE);

  var handler = Registry.lookupObject(DirectHandler);

  context["dartApi"] = (dynamic callback) =>
      handler.dartApi.then((api) => callback.apply([api]));

  context["directCall"] = (String base,
          String application,
          String path,
          Map<String, dynamic> decodedDirectRequest,
          Map<String, dynamic> headers1,
          callback) =>
      Chain.capture(() {
        var headers = {};

        headers1.forEach((String key, value) {
          key = key.toLowerCase();

          if (value == null) {
            headers[key] = null;
          } else if (value is List) {
            headers[key] = (value as List)
                .map((value2) => value2 != null ? value2.toString() : null)
                .toList();
          } else {
            headers[key] = [value.toString()];
          }
        });

        return handler.directCall(new ClientDirectCall(
            base, application, path, decodedDirectRequest, headers,
            (jsonResponse, responseHeaders) {
          callback.apply([jsonResponse, new JsObject.jsify(responseHeaders)]);
        }));
      }, onError: (e, s) => _libraryLogger.severe("Uncaught error", e, s));

  context["onDartLoaded"].apply([]);
}

class ClientDirectCall implements DirectCall {
  final String base;
  final String application;
  final String path;
  final Map<String, dynamic> decodedDirectRequest;
  final Map<String, List<String>> headers;
  final DirectCallback callback;

  ClientDirectCall(this.base, this.application, this.path,
      this.decodedDirectRequest, this.headers, this.callback);

  Future onRequest(
      Future directCall(
          String base,
          String application,
          String path,
          Map<String, dynamic> decodedDirectRequest,
          Map<String, List<String>> headers,
          DirectCallback callback)) {
    return directCall(
        base, application, path, decodedDirectRequest, headers, callback);
  }
}
