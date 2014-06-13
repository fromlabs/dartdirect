part of directserver;

class DirectIsolateHandler {

	DirectIsolateHandler() {
		DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
	}

	void handleRequest(dynamic message) {
		var sendPort = message["sendPort"];
		new DirectHandler().directCall(message["base"], message["path"], message["jsonRequest"], (jsonResponse) {
			sendPort.send({
				"action": "write",
				"jsonResponse": jsonResponse
			});
			sendPort.send({
				"action": "close"
			});
		});
	}
}

class DevDirectServer extends AbstractDirectServer {

	final Uri _isolateUri;

	DevDirectServer({String host: "0.0.0.0", num port: 8081, Uri webUri, Uri isolateUri})
			: super(host: host, port: port, webUri: webUri),
			  this._isolateUri = isolateUri;

	void handleRequest(String base, String path, String jsonRequest, HttpRequest request) {
		var receivePort = new ReceivePort();
		receivePort.listen((message) {
			if (message["action"] == "write") {
				request.response.headers.contentType = new ContentType("application", "json", charset: "utf-8");
				request.response.write(message["jsonResponse"]);
			} else if (message["action"] == "close") {
				request.response.close();
			}
		});
		Isolate.spawnUri(_isolateUri, null, {
			"sendPort": receivePort.sendPort,
			"base": base,
			"path": path,
			"jsonRequest": jsonRequest
		});
	}
}

class DirectServer extends AbstractDirectServer {

	DirectServer({String host: "0.0.0.0", num port: 8081, Uri webUri}) : super(host: host, port: port, webUri: webUri) {
		DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
	}

	void handleRequest(String base, String path, String jsonRequest, HttpRequest request) {
		new DirectHandler().directCall(base, path, jsonRequest, (jsonResponse) {
			request.response.headers.contentType = new ContentType("application", "json", charset: "utf-8");
			request.response.write(jsonResponse);
			request.response.close();
		});
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

	void handleRequest(String base, String path, String jsonRequest, HttpRequest request);

	void start() {
		runZoned(() {
			HttpServer.bind(_host, _port).then((server) {
				print("Server ${server.address}:${server.port} on ${new File.fromUri(_webUri).resolveSymbolicLinksSync()}");

				server.listen((HttpRequest request) {
					request.response.headers.add("Access-Control-Allow-Origin", "*");
					request.response.headers.add("Access-Control-Allow-Headers", "X-Requested-With,Content-Type");
					request.response.headers.set("Access-Control-Allow-Methods", "POST");
					if (request.method == "OPTIONS") {
						request.response.close();
					} else {
						String path = request.uri.path;
						if (path == "/direct" || path == "/direct/api") {
							String base;

							if (path == "/direct/api") {
								if (request.uri.queryParameters.containsKey("standalone")) {
									base = request.requestedUri.origin;
								} else {
									base = null;
								}
							}

							StringBuffer buffer = new StringBuffer();
							request.transform(new Utf8Decoder()).listen((String chunk) => buffer.write(chunk), onDone: () {
								handleRequest(base, path, buffer.toString(), request);
							});
						} else {
							if (path == "/") {
								path = "/index.html";
							}

							final File file = new File("${_webUri}${path}");
							file.exists().then((bool found) {
								if (found) {
									var mimeType = lookupMimeType(path.split("\\.").last);
									if (mimeType != null) {
										var split = mimeType.split("/");
										request.response.headers.contentType = new ContentType(split[0], split[1]);
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
		}, onError: (e, stackTrace) => print('Oh noes! $e $stackTrace'));
	}
}
