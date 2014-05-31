part of directclient;

void initializeClientDirectHandling() {
	DIRECT_ENVIROMENT = context["DIRECT_ENVIROMENT"];

	context["dartApi"] = () {
		return new DirectHandler().dartApi;
	};

	context["directCall"] = (String base, String path, String jsonRequest, dynamic callback) {
		return new DirectHandler().directCall(base, path, jsonRequest, (jsonResponse) {
			callback.apply([jsonResponse]);
		});
	};

	context["onDartLoaded"].apply([]);
}
