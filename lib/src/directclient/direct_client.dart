part of directclient;

// TODO come intercettiamo la close?

void initializeClientDirectHandling(Type module, [Map<String, dynamic> parameters = const {}]) {
	DIRECT_ENVIROMENT = context["DIRECT_ENVIROMENT"];

	Registry.load(module, parameters)
	.then((_) => Registry.openScope(Scope.ISOLATE))
	.then((_) {
		var handler = Registry.lookupObject(DirectHandler);

		context["dartApi"] = (dynamic callback) => handler.dartApi.then((api) => callback.apply([api]));

		// TODO recupero gli headers
		Map<String, List<String>> headers;

		// TODO aggiungere response headers

		context["directCall"] = (String base, String path, String jsonRequest, dynamic callback) => handler.directCall(base, path, jsonRequest, headers, (jsonResponse, responseHeaders) => callback.apply([jsonResponse, responseHeaders]));

		context["onDartLoaded"].apply([]);
	});
}
