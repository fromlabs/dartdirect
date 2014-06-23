part of directclient;

// TODO come intercettiamo la close?

void initializeClientDirectHandling(Type module, [Map<String, dynamic> parameters = const {}]) {
	DIRECT_ENVIROMENT = context["DIRECT_ENVIROMENT"];

	Registry.load(module, parameters)
	.then((_) => Registry.openScope(Scope.ISOLATE))
	.then((_) {
		var handler = Registry.lookupObject(DirectHandler);

		context["dartApi"] = (dynamic callback) => handler.dartApi.then((api) => callback.apply([api]));

		context["directCall"] = (String base, String path, String jsonRequest, dynamic callback) => handler.directCall(base, path, jsonRequest, (jsonResponse) => callback.apply([jsonResponse]));

		context["onDartLoaded"].apply([]);
	});
}
