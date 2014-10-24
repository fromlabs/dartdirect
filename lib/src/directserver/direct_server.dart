part of directserver;

class DevDirectIsolateHandler {

  final Type module;

  final Map<String, dynamic> parameters;

  DevDirectIsolateHandler(this.module, [this.parameters = const {}]) {
    DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
  }

  void handleRequest(dynamic message) {
    Registry.load(
        module,
        parameters).then(
            (_) =>
                Registry.openScope(
                    Scope.ISOLATE)).then(
                        (_) =>
                            Registry.lookupObject(
                                DirectHandler).directCall(
                                    new DevServerDirectCall(message))).catchError((error) {
      print("Gestire errore generico: $error");
      if (error is Error) {
        print(error.stackTrace);
      }
    }).whenComplete(
        () => Registry.closeScope(Scope.ISOLATE)).whenComplete(() => Registry.unload());
  }
}

class DevDirectServer extends AbstractDirectServer {

  final Uri _isolateUri;

  DevDirectServer({String host: "0.0.0.0", num port: 8081, Uri webUri,
      Uri isolateUri})
      : super(host: host, port: port, webUri: webUri),
        this._isolateUri = isolateUri;

  void handleRequest(String base, String application, String path,
      HttpRequest request) {
    var receivePort = new ReceivePort();
    receivePort.listen((message) {
      if (message["action"] == "ready") {
        SendPort sendPort = message["sendPort"];
        request.listen((data) {
          sendPort.send({
            "action": "data",
            "data": data
          });
        }, onDone: () {
          sendPort.send({
            "action": "close"
          });
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

    Isolate.spawnUri(_isolateUri, null, {
      "sendPort": receivePort.sendPort,
      "base": base,
      "application": application,
      "path": path,
      "headers": headers
    });
  }
}

class DirectServer extends AbstractDirectServer {

  final Type module;

  final Map<String, dynamic> parameters;

  DirectServer({String host: "0.0.0.0", num port: 8081, Uri webUri, this.module,
      this.parameters: const {}})
      : super(host: host, port: port, webUri: webUri) {
    DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
  }

  @override
  Future start() {
    ProcessSignal.SIGTERM.watch().listen((ProcessSignal signal) {
      print("Catch TERMINATION signal");
      this._stop().whenComplete(() => exit(0));
    });

    ProcessSignal.SIGINT.watch().listen((ProcessSignal signal) {
      print("Catch INTERUPT signal");
      this._stop().whenComplete(() => exit(0));
    });

    return Registry.load(
        module,
        parameters).then(
            (_) => Registry.openScope(Scope.ISOLATE)).then((_) => super.start());
  }

  Future _stop() =>
      Registry.closeScope(Scope.ISOLATE).whenComplete(() => Registry.unload());

  void handleRequest(String base, String application, String path,
      HttpRequest request) {
    Map<String, List<String>> headers = {};
    request.headers.forEach((name, values) => headers[name] = values);

    Registry.lookupObject(
        DirectHandler).directCall(
            new ServerDirectCall(base, application, path, request));
  }
}

abstract class AbstractDirectServer {

  final String _host;

  final num _port;

  final Uri _webUri;

  AbstractDirectServer({String host: "0.0.0.0", num port: 8081, Uri webUri})
      : this._webUri = webUri,
        this._host = host,
        this._port = port;

  void handleRequest(String base, String application, String path,
      HttpRequest request);

  Future start() {
    return HttpServer.bind(_host, _port).then((server) {
      print(
          "Server ${server.address}:${server.port} on ${new File.fromUri(_webUri).resolveSymbolicLinksSync()}");

      server.autoCompress = true;

      server.listen((HttpRequest request) {
        // request.response.headers.add("Access-Control-Allow-Origin", "*");

        // request.response.headers.add("Access-Control-Allow-Headers", "X-Requested-With,Content-Type");
        // request.response.headers.set("Access-Control-Allow-Methods", "POST");

        request.response.headers.remove("X-Frame-Options", "SAMEORIGIN");

        if (request.method == "OPTIONS") {
          request.response.close();
        } else {
          if ((request.uri.pathSegments.length > 0 &&
              request.uri.pathSegments[0] == "direct") ||
              (request.uri.pathSegments.length > 1 &&
                  request.uri.pathSegments[1] == "direct")) {
            String application =
                request.uri.pathSegments.length > 1 && request.uri.pathSegments[1] == "direct" ?
                    request.uri.pathSegments[0] :
                    null;
            String path = "/" + request.uri.pathSegments.join("/");
            if (application != null) {
              path = "/" + request.uri.pathSegments.sublist(1).join("/");
            } else {
              path = "/" + request.uri.pathSegments.join("/");
            }

            if (path == "/direct/api") {
              request.response.headers.contentType =
                  new ContentType("application", "javascript", charset: "utf-8");
            } else {
              request.response.headers.contentType =
                  new ContentType("application", "json", charset: "utf-8");
            }

            handleRequest(null, application, path, request);
/*
					} else if (path.endsWith("/uploadpersister")) {
						// SERVE SOLO PER SELIALIZZARE DEGLI UPLOAD PER FARE DEI TEST
						var name = "REQUEST_${new DateTime.now().millisecondsSinceEpoch}";

						var headersFile = new File("requests/${name}_headers.json");
						headersFile.createSync(recursive: true);
						var writeSink = null;
						try {
							var JSON = new JsonEncoder.withIndent("\t");
							writeSink = headersFile.openWrite();
							var headers = {};
							request.headers.forEach((key, values) => headers[key] = values);
							writeSink.write(JSON.convert(headers));
						} finally {
							if (writeSink != null) {
								writeSink.close();
							}
						}

						var contentFile = new File("requests/${name}.request");
						contentFile.createSync(recursive: true);
						writeSink = null;
						writeSink = contentFile.openWrite();
						writeSink.addStream(request).whenComplete(() {
							if (writeSink != null) {
								writeSink.close();
							}

							request.response.close();
						});
*/
          } else {
            print("Serving static request: ${request.uri}");

            String path = "/" + request.uri.pathSegments.join("/");
            var absolutePath = _webUri.path + path;

            if (FileSystemEntity.isDirectorySync(absolutePath)) {
              absolutePath +=
                  (absolutePath.endsWith("/") ? "" : "/") + "index.html";
            }

            final File file = new File(absolutePath);
            file.exists().then((bool found) {
              if (found) {
                var mimeType = lookupMimeType(absolutePath.split("\\.").last);
                if (mimeType != null) {
                  var split = mimeType.split("/");
                  request.response.headers.contentType =
                      new ContentType(split[0], split[1]);
                }

                file.openRead().pipe(request.response).catchError((e) {});
              } else {
                request.response.statusCode = HttpStatus.NOT_FOUND;
                request.response.close();
              }
            });
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

  Future onRequest(Future directCall(String base, String application,
      String path, String json, Map<String, List<String>> headers,
      MultipartRequest multipartRequest, DirectCallback callback)) {
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
      request2.stream.transform(
          converter).listen((MultipartRequest multipartRequest) {
        buffer.write("""
					{
						"action": "$multipartAction",
						"method": "$multipartMethod",
						"type": "upload",
						"tid": 1
					}
				""");

        resultFuture = directCall(
            base,
            application,
            path,
            buffer.toString(),
            headers,
            multipartRequest,
            (jsonResponse, responseHeaders) {

          responseHeaders.forEach(
              (name, value) => request.response.headers.add(name, value));
          request.response.write(jsonResponse);
          request.response.close();
        });
      });
    } else {
      request2.stream.transform(
          UTF8.decoder).listen((String chunk) => buffer.write(chunk));
    }

    request.listen((data) => request2.add(data), onDone: () {
      request2.close().then((_) {
        if (resultFuture != null) {
          return resultFuture;
        } else {
          return directCall(
              base,
              application,
              path,
              buffer.toString(),
              headers,
              null,
              (jsonResponse, responseHeaders) {
            responseHeaders.forEach(
                (name, value) => request.response.headers.add(name, value));
            request.response.write(jsonResponse);
            request.response.close();
          });
        }
      }).then(
          (_) =>
              completer.complete()).catchError((error) => completer.completeError(error));
    });

    return completer.future;
  }
}

class DevServerDirectCall implements DirectCall {
  final dynamic message;

  DevServerDirectCall(this.message);

  Future onRequest(Future directCall(String base, String application,
      String path, String json, Map<String, List<String>> headers,
      MultipartRequest multipartRequest, DirectCallback callback)) {

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
      request.stream.transform(
          converter).listen((MultipartRequest multipartRequest) {
        buffer.write("""
						{
							"action": "$multipartAction",
							"method": "$multipartMethod",
							"type": "upload",
							"tid": 1
						}
					""");

        resultFuture = directCall(
            base,
            application,
            path,
            buffer.toString(),
            headers,
            multipartRequest,
            (jsonResponse, responseHeaders) {
          sendPort.send({
            "action": "response",
            "jsonResponse": jsonResponse,
            "responseHeaders": responseHeaders
          });
        });
      });
    } else {
      request.stream.transform(
          UTF8.decoder).listen((String chunk) => buffer.write(chunk));
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
                base,
                application,
                path,
                buffer.toString(),
                headers,
                null,
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
        }).catchError((error) {
          completer.completeError(error);
        }).whenComplete(() {
          receivePort.close();
        });
      }
    });
    sendPort.send({
      "action": "ready",
      "sendPort": receivePort.sendPort
    });
    return completer.future;
  }
}
