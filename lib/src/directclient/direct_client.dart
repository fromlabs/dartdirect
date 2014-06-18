part of directclient;

ScopeContext _isolateScopeContext;

// TODO come intercettiamo la close?

void initializeClientDirectHandling(Type module, [Map<String, dynamic> parameters = const {}]) {
	DIRECT_ENVIROMENT = context["DIRECT_ENVIROMENT"];

	Registry.load(module, parameters).then((_) => Registry.initializeScope(ScopeContext.ISOLATE, new MapScopeContext())).then((context) => _isolateScopeContext = context).then((_) {
		var handler = new DirectHandler(_isolateScopeContext);

		context["dartApi"] = (dynamic callback) => handler.dartApi.then((api) => callback.apply([api]));

		context["directCall"] = (String base, String path, String jsonRequest, dynamic callback) => handler.directCall(base, path, jsonRequest, (jsonResponse) => callback.apply([jsonResponse]));

		context["onDartLoaded"].apply([]);
	});
}
