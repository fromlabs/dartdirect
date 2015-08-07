part of directclient;

// TODO come intercettiamo la close?

void initializeClientDirectHandling(Type module,
    [Map<String, dynamic> parameters = const {}]) {
  DIRECT_ENVIROMENT = context["DIRECT_ENVIROMENT"];

  Registry.load(module, parameters).then((_) => Registry.openScope(Scope.ISOLATE)).then((_) {
    var handler = Registry.lookupObject(DirectHandler);

    context["dartApi"] = (dynamic callback) =>
        handler.dartApi.then((api) => callback.apply([api]));

    context["directCall"] = (String base, String application, String path,
        String jsonRequest, callback) {
      return handler.directCall(new ClientDirectCall(base, application, path,
          jsonRequest, (jsonResponse, responseHeaders) {
        callback.apply([jsonResponse, responseHeaders]);
      }));
    };

    context["onDartLoaded"].apply([]);
  });
}

class ClientDirectCall implements DirectCall {
  final String base;
  final String application;
  final String path;
  final String jsonRequest;
  final DirectCallback callback;

  ClientDirectCall(
      this.base, this.application, this.path, this.jsonRequest, this.callback);

  Future onRequest(Future directCall(String base, String application,
      String path, String json, Map<String, List<String>> headers,
      MultipartRequest multipartRequest, DirectCallback callback)) {
    // TODO recupero gli headers
    Map<String, List<String>> headers = {};

    return directCall(
        base, application, path, jsonRequest, headers, null, callback);
  }
}
