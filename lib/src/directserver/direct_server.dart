part of directserver;

class DevDirectIsolateHandler {

	final Type module;

	final Map<String, dynamic> parameters;

	DevDirectIsolateHandler(this.module, [this.parameters = const {}]) {
		DIRECT_ENVIROMENT = DirectEnviroment.SERVER;
	}

	void handleRequest(dynamic message) {
		var isolateScopeContext;
		Registry.load(module, parameters).then((_) => Registry.initializeScope(ScopeContext.ISOLATE, new MapScopeContext())).then((context) => isolateScopeContext = context).then((_) {
			SendPort sendPort = message["sendPort"];
			return new DirectHandler(isolateScopeContext).directCall(message["base"], message["path"], message["jsonRequest"], (jsonResponse) {
				sendPort.send({
					"action": "write",
					"jsonResponse": jsonResponse
				});
				sendPort.send({
					"action": "close"
				});
			});
		}).whenComplete(() => Registry.deinitializeScope(isolateScopeContext)).whenComplete(() => Registry.unload());
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

	final Type module;

	final Map<String, dynamic> parameters;

	ScopeContext _isolateScopeContext;

	DirectServer({String host: "0.0.0.0", num port: 8081, Uri webUri, this.module, this.parameters: const {}}) : super(host: host, port: port, webUri: webUri) {
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

		return Registry.load(module, parameters).then((_) => Registry.initializeScope(ScopeContext.ISOLATE, new MapScopeContext())).then((context) => _isolateScopeContext = context).then((_) => super.start());
	}

	Future _stop() {
		return new Future.sync(() => Registry.deinitializeScope(_isolateScopeContext)).whenComplete(() => Registry.unload());
	}

	void handleRequest(String base, String path, String jsonRequest, HttpRequest request) {
		new DirectHandler(_isolateScopeContext).directCall(base, path, jsonRequest, (jsonResponse) {
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

	Future start() {
		return HttpServer.bind(_host, _port).then((server) {
			print("Server ${server.address}:${server.port} on ${new File.fromUri(_webUri).resolveSymbolicLinksSync()}");

			server.listen((HttpRequest request) {
				// request.response.headers.add("Access-Control-Allow-Origin", "*");
				// request.response.headers.add("Access-Control-Allow-Headers", "X-Requested-With,Content-Type");
				// request.response.headers.set("Access-Control-Allow-Methods", "POST");

				if (request.method == "OPTIONS") {
					request.response.close();
				} else {
					String path = "/" + request.uri.pathSegments.join("/");
					if (path.endsWith("direct") || path.endsWith("direct/api")) {
						StringBuffer buffer = new StringBuffer();
						request.transform(new Utf8Decoder()).listen((String chunk) => buffer.write(chunk), onDone: () {
							handleRequest(null, path, buffer.toString(), request);
						});
					} else {
						if (path.endsWith("/")) {
							path += "index.html";
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
	}
}
