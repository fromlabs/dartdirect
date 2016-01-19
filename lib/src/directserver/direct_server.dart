part of dartdirect.server;

class DevDirectIsolateHandler extends Loggable {
  final RegistryModule module;

  DevDirectIsolateHandler(this.module) {
    DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
  }

  Future handleRequest(dynamic message) async {
    try {
      await Registry.load(module);

      await Registry.openScope(Scope.ISOLATE);

      await Registry
          .lookupObject(DirectHandler)
          .directCall(new DevServerDirectCall(message));
    } catch (error, stacktrace) {
      severe("Handler error", error, stacktrace);
    } finally {
      await Registry.closeScope(Scope.ISOLATE);

      await Registry.unload();
    }
  }
}

class DevDirectServer extends AbstractDirectServer {
  final Uri _isolateUri;
  final List<String> _isolateArgs;

  DevDirectServer(
      {String host: "0.0.0.0",
      num port: 8081,
      Map<String, String> hostApplicationMappings: const {},
      Uri webUri,
      Uri isolateUri,
      List<String> isolateArgs})
      : super(
            host: host,
            port: port,
            webUri: webUri,
            hostApplicationMappings: hostApplicationMappings,
            autoCompress: false),
        this._isolateUri = isolateUri,
        this._isolateArgs = isolateArgs;

  void handleRequest(
      String base, String application, String path, HttpRequest request) {
    var receivePort = new ReceivePort();
    receivePort.listen((message) {
      if (message["action"] == "ready") {
        SendPort sendPort = message["sendPort"];
        request.listen((data) {
          sendPort.send({"action": "data", "data": data});
        }, onDone: () {
          sendPort.send({"action": "close"});
        });
      } else if (message["action"] == "response") {
        message["responseHeaders"].forEach(
            (name, value) => request.response.headers.add(name, value));
        request.response.write(message["jsonResponse"]);
        request.response.close();
      }
    });

    Map<String, List<String>> headers = {};
    request.headers.forEach((name, values) => headers[name] = values);

    Isolate.spawnUri(_isolateUri, _isolateArgs, {
      "sendPort": receivePort.sendPort,
      "base": base,
      "application": application,
      "path": path,
      "headers": headers
    });
  }
}

class DirectServer extends AbstractDirectServer {
  final RegistryModule module;

  DirectServer(
      {String host: "0.0.0.0",
      num port: 8081,
      Map<String, String> hostApplicationMappings: const {},
      Uri webUri,
      this.module})
      : super(
            host: host,
            port: port,
            webUri: webUri,
            hostApplicationMappings: hostApplicationMappings) {
    DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
  }

  @override
  Future start() async {
    ProcessSignal.SIGTERM.watch().listen((ProcessSignal signal) {
      info("Catch TERMINATION signal");
      this._stop().whenComplete(() => exit(0));
    });

    ProcessSignal.SIGINT.watch().listen((ProcessSignal signal) {
      info("Catch INTERUPT signal");
      this._stop().whenComplete(() => exit(0));
    });

    await Registry.load(module);

    await Registry.openScope(Scope.ISOLATE);

    await super.start();
  }

  Future _stop() =>
      Registry.closeScope(Scope.ISOLATE).whenComplete(() => Registry.unload());

  void handleRequest(
      String base, String application, String path, HttpRequest request) {
    Registry
        .lookupObject(DirectHandler)
        .directCall(new ServerDirectCall(base, application, path, request));
  }
}

abstract class AbstractDirectServer extends Loggable {
  final String _host;

  final num _port;

  final Uri _webUri;

  final bool _autoCompress;

  final Map<String, String> _hostApplicationMappings;

  AbstractDirectServer(
      {String host: "0.0.0.0",
      num port: 8081,
      Map<String, String> hostApplicationMappings: const {},
      Uri webUri,
      bool autoCompress: true})
      : this._hostApplicationMappings = hostApplicationMappings,
        this._webUri = webUri,
        this._host = host,
        this._port = port,
        this._autoCompress = autoCompress;

  Logger createLogger() {
    return new Logger("dartdirect.server.$runtimeType");
  }

  void handleRequest(
      String base, String application, String path, HttpRequest request);

  Future start() {
    return HttpServer.bind(_host, _port).then((server) {
      info(
          "Server ${server.address}:${server.port} on ${new File.fromUri(_webUri).resolveSymbolicLinksSync()}");

      info("Host application mappings: ${_hostApplicationMappings}");

      server.autoCompress = this._autoCompress;

      server.defaultResponseHeaders.removeAll("X-Frame-Options");

      server.listen((HttpRequest request) async {
        request.response.headers.add("Access-Control-Allow-Origin", "*");
        request.response.headers.add("Access-Control-Allow-Headers",
            "X-Requested-With,Content-Type,environment,locale,code-base,domain,authorization");
        request.response.headers
            .add("Access-Control-Expose-Headers", "authorization");
        request.response.headers.set("Access-Control-Allow-Methods", "POST");

        // request.response.headers.remove("X-Frame-Options", "SAMEORIGIN");
        // request.response.headers.removeAll("X-Frame-Options");

        if (request.method == "OPTIONS") {
          request.response.close();
        } else {
          fine("Serving request: ${request.uri}");

          var directUri;
          var host = request.headers.host;
          var application = this._hostApplicationMappings[host];
          var explicitApplication = application == null;
          var parts = request.uri.pathSegments;

          if (application != null) {
            directUri = parts.length > 0 && parts[0] == "direct"
                ? "/" + parts.join("/")
                : null;
          } else if (parts.length > 1 && parts[1] == "direct") {
            application = parts[0];
            directUri = "/" + parts.sublist(1).join("/");
          } else if (parts.length > 0 && parts[0] == "direct") {
            application = null;
            directUri = "/" + parts.join("/");
          } else {
            application = null;
            directUri = null;
          }

          if (directUri != null) {
            if (directUri == "/direct/api") {
              fine("Direct api request");

              request.response.headers.contentType = new ContentType(
                  "application", "javascript",
                  charset: "utf-8");

              handleRequest(null, application, "/direct/api", request);
            } else {
              fine("Direct action request: $directUri");

              request.response.headers.contentType =
                  new ContentType("application", "json", charset: "utf-8");

              handleRequest(null, application, directUri, request);
            }
          } else {
            fine("Static content request: ${request.uri}");

            var absolutePath = _webUri.path.endsWith("/")
                ? _webUri.path.substring(0, _webUri.path.length - 1)
                : _webUri.path;

            if (!explicitApplication) {
              absolutePath += "/$application";
            }

            absolutePath += request.uri.path;

            if (await FileSystemEntity.isDirectory(absolutePath)) {
              if (request.uri.path.endsWith("/")) {
                absolutePath += "index.html";
              } else {
                var fragment =
                    request.uri.hasFragment ? "#${request.uri.fragment}" : "";
                var query = request.uri.hasQuery ? "?${request.uri.query}" : "";

                request.response.redirect(
                    request.uri.resolve("${request.uri.path}/$fragment$query"));
                return;
              }
            }

            final File file = new File(Uri.decodeFull(absolutePath));

            bool found = await file.exists();

            if (found) {
              var mimeType = lookupMimeType(absolutePath.split("\\.").last);
              if (mimeType != null) {
                var split = mimeType.split("/");
                request.response.headers.contentType =
                    new ContentType(split[0], split[1]);
              }

              await file.openRead().pipe(request.response);
            } else {
              request.response.statusCode = HttpStatus.NOT_FOUND;
              await request.response.close();
            }
          }
        }
      });
    });
  }
}

class ServerDirectCall implements DirectCall {
  final String base;
  final String application;
  final String path;
  final HttpRequest request;

  ServerDirectCall(this.base, this.application, this.path, this.request);

  Future onRequest(Future directCall(
      String base,
      String application,
      String path,
      String json,
      Map<String, List<String>> headers,
      MultipartRequest multipartRequest,
      DirectCallback callback)) {
    Completer completer = new Completer();
    Map<String, List<String>> headers = {};
    request.headers.forEach((name, values) => headers[name] = values);

    StreamController<List<int>> request2 = new StreamController(sync: true);
    StringBuffer buffer = new StringBuffer();

    Future resultFuture;
    String multipartAction;
    String multipartMethod;
    if (path != "/direct/api") {
      var splits = path.split("/");
      if (splits.length == 4) {
        multipartAction = splits[2];
        multipartMethod = splits[3];
      }
    }
    if (multipartAction != null) {
      MultipartConverter converter = new MultipartConverter(headers);
      request2.stream
          .transform(converter)
          .listen((MultipartRequest multipartRequest) {
        buffer.write("""
					{
						"action": "$multipartAction",
						"method": "$multipartMethod",
						"type": "upload",
						"tid": 1
					}
				""");

        resultFuture = directCall(base, application, path, buffer.toString(),
            headers, multipartRequest, (jsonResponse, responseHeaders) {
          responseHeaders.forEach(
              (name, value) => request.response.headers.add(name, value));
          request.response.write(jsonResponse);
          request.response.close();
        });
      });
    } else {
      request2.stream
          .transform(UTF8.decoder)
          .listen((String chunk) => buffer.write(chunk));
    }

    request.listen((data) => request2.add(data), onDone: () {
      request2.close().then((_) {
        if (resultFuture != null) {
          return resultFuture;
        } else {
          return directCall(
              base, application, path, buffer.toString(), headers, null,
              (jsonResponse, responseHeaders) {
            responseHeaders.forEach(
                (name, value) => request.response.headers.add(name, value));
            request.response.write(jsonResponse);
            request.response.close();
          });
        }
      }).then((_) => completer.complete()).catchError(
          (error, stacktrace) => completer.completeError(error, stacktrace));
    });

    return completer.future;
  }
}

class DevServerDirectCall implements DirectCall {
  final dynamic message;

  DevServerDirectCall(this.message);

  Future onRequest(Future directCall(
      String base,
      String application,
      String path,
      String json,
      Map<String, List<String>> headers,
      MultipartRequest multipartRequest,
      DirectCallback callback)) {
    Completer completer = new Completer();
    SendPort sendPort = message["sendPort"];
    String base = message["base"];
    String application = message["application"];
    String path = message["path"];
    Map<String, List<String>> headers = message["headers"];
    var receivePort = new ReceivePort();
    StreamController<List<int>> request = new StreamController(sync: false);

    StringBuffer buffer = new StringBuffer();

    Future resultFuture;
    String multipartAction;
    String multipartMethod;
    if (path != "/direct/api") {
      var splits = path.split("/");
      if (splits.length == 4) {
        multipartAction = splits[2];
        multipartMethod = splits[3];
      }
    }
    if (multipartAction != null) {
      MultipartConverter converter = new MultipartConverter(headers);
      request.stream
          .transform(converter)
          .listen((MultipartRequest multipartRequest) {
        buffer.write("""
						{
							"action": "$multipartAction",
							"method": "$multipartMethod",
							"type": "upload",
							"tid": 1
						}
					""");

        resultFuture = directCall(base, application, path, buffer.toString(),
            headers, multipartRequest, (jsonResponse, responseHeaders) {
          sendPort.send({
            "action": "response",
            "jsonResponse": jsonResponse,
            "responseHeaders": responseHeaders
          });
        });
      });
    } else {
      request.stream
          .transform(UTF8.decoder)
          .listen((String chunk) => buffer.write(chunk));
    }

    receivePort.listen((message) {
      if (message["action"] == "data") {
        request.add(message["data"]);
      } else if (message["action"] == "close") {
        request.close().then((_) {
          if (resultFuture != null) {
            return resultFuture;
          } else {
            return directCall(
                base, application, path, buffer.toString(), headers, null,
                (jsonResponse, responseHeaders) {
              sendPort.send({
                "action": "response",
                "jsonResponse": jsonResponse,
                "responseHeaders": responseHeaders
              });
            });
          }
        }).then((_) {
          completer.complete();
        }).catchError((error, stacktrace) {
          completer.completeError(error, stacktrace);
        }).whenComplete(() {
          receivePort.close();
        });
      }
    });
    sendPort.send({"action": "ready", "sendPort": receivePort.sendPort});
    return completer.future;
  }
}
