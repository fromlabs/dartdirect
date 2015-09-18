part of directclient;

// TODO come intercettiamo la close?

void initializeClientDirectHandling(Type module,
    [Map<String, dynamic> parameters = const {}]) {
  DIRECT_ENVIROMENT = context["DIRECT_ENVIROMENT"];

  Registry.load(module, parameters).then((_) => Registry.openScope(Scope.ISOLATE)).then((_) {
    var handler = Registry.lookupObject(DirectHandler);

    context["dartApi"] = (dynamic callback) =>
        handler.dartApi.then((api) => callback.apply([api]));

    context["directCall"] = (String base, String domain, String application, String path,
                             String jsonRequest, String jsonHeaders, callback) {

      var headers = {};
      var headers1 = JSON.decode(jsonHeaders);
      headers1.forEach((String key, value) {
        key = key.toLowerCase();

        if (value == null) {
          headers[key] = null;
        } else if (value is List) {
          headers[key] = (value as List).map((value2) => value2 != null ? value2.toString() : null).toList();
        } else {
          headers[key] = [value.toString()];
        }
      });

      return handler.directCall(new ClientDirectCall(base, domain, application, path,
          jsonRequest, headers, (jsonResponse, responseHeaders) {
        callback.apply([jsonResponse, responseHeaders]);
      }));
    };

    context["onDartLoaded"].apply([]);
  });
}

class ClientDirectCall implements DirectCall {
  final String base;
  final String domain;
  final String application;
  final String path;
  final String jsonRequest;
  final Map<String, List<String>> headers;
  final DirectCallback callback;

  ClientDirectCall(
      this.base, this.domain, this.application, this.path, this.jsonRequest, this.headers, this.callback);

  Future onRequest(Future directCall(String base, String domain, String application,
      String path, String json, Map<String, List<String>> headers,
      MultipartRequest multipartRequest, DirectCallback callback)) {

    return directCall(
        base, domain, application, path, jsonRequest, headers, null, callback);
  }
}
