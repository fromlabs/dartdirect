part of directbackendapi;

class DirectRequest {
	String _domain;

	String _action;

	String _method;

	List<dynamic> _data;

	void _registerRequest(String domain, String action, String method, List<dynamic> data) {
		_domain = domain;
		_action = action;
		_method = method;
		_data = data;
	}

	String get domain => _domain;

	String get action => _action;

	String get method => _method;

	List<dynamic> get data => _data;
}

class DirectManager {

	Map<String, Type> _directActions = {};
	Map<String, Map<String, MethodMirror>> _directMethods = {};

	final String enviroment;

	DirectManager(this.enviroment) {
		print("Direct Manager registered in $enviroment enviroment");
	}

	void registerDirectAction(Type actionClazz) {
		print("Register direct action: $actionClazz");

		// recupero metodi
		Map<String, MethodMirror> methods = new Map<String, MethodMirror>();
		var annotationMirror = reflect(DirectMethod);
		reflectClass(actionClazz).declarations.forEach((methodSymbol, methodMirror) {
			if (methodMirror is MethodMirror && methodMirror.metadata.contains(annotationMirror)) {
				var name = MirrorSystem.getName(methodSymbol);
				print("Register direct method: ${name}");

				methods[name] = methodMirror;
			}
		});

		var actionName = actionClazz.toString();
		_directActions[actionName] = actionClazz;
		_directMethods[actionName] = methods;
	}

	void deregisterAllDirectActions() {
		print("Deregister all direct actions");

		_directActions.clear();
		_directMethods.clear();
	}

	String get dartApi => _getDartApi(null, null, true);

	Future directCall(String base, String path, String json, DirectCallback callback) {
		Completer completer = new Completer();

		if (path.endsWith("direct/api")) {
			var domain = path.substring(1, path.length - "direct/api".length);

			callback(_getDartApi(base, domain, false));

			completer.complete();
		} else if (path.endsWith("direct")) {
			var domain = path != "direct" ? path.substring(1, path.length - "direct".length) : "";

			// read parameters
			var directRequest = JSON.decode(json);

			String action = directRequest["action"];
			String method = directRequest["method"];
			int tid = directRequest["tid"];
			String type = directRequest["type"];

			var directResponse = {
				"action": action,
				"method": method,
				"tid": tid,
				"type": type
			};

			var result = _invokeDirectService(domain, action, method, directRequest["data"]);

			if (result is! Future) {
				result = new Future.value(result);
			}

			// TODO gestione errore

			result.then((value) {
				directResponse["result"] = value;

				callback(JSON.encode(directResponse));

				completer.complete();
			});
		} else {
			// TODO gestione errore
			completer.completeError("Path not valid: $path");
		}

		return completer.future;
	}

	String _getDartApi(String base, String domain, bool localApi) {
		StringBuffer buffer = new StringBuffer();

		buffer.write("var remotingApi = ");

		buffer
				..write(JSON.encode(_getDirectApiMap(base, domain, localApi)))
				..write(";")
				..write("\r\n");

		buffer
				..write("onDirectApiLoaded(remotingApi);")
				..write("\r\n");
		return buffer.toString();
	}

	Map<String, dynamic> _getDirectApiMap(String base, String domain, bool localApi) {
		Map<String, dynamic> apiMap = {};

		StringBuffer url = new StringBuffer();
		if (base != null) {
			url.write("base/");
		}
		url.write("direct");

		apiMap["domain"] = domain;
		apiMap["url"] = url.toString();
		apiMap["type"] = localApi ? "dart" : "remoting";
		apiMap["maxRetries"] = "0";
		apiMap["timeout"] = "300000"; // 5 minuti
		apiMap["enableBuffer"] = false;

		Map<String, dynamic> actionMap = {};
		apiMap["actions"] = actionMap;

		_directMethods.forEach((action, Map methods) {
			List<Object> methodList = [];
			actionMap[action] = methodList;

			methods.forEach((method, mirror) {
				Map<String, Object> methodMap = {};
				methodList.add(methodMap);
				methodMap["name"] = method;
				methodMap["len"] = mirror.parameters.length;
			});
		});

		return apiMap;
	}

	_invokeDirectService(String domain, String action, String method, List<dynamic> data) {
		DirectRequest directRequest = Registry.lookupObject(DirectRequest);
		directRequest._registerRequest(domain, action, method, data);

		InstanceMirror result;
		var actionType = _directActions[action];
		var service = Registry.lookupObject(actionType);
		var serviceMirror = reflect(service);
		MethodMirror methodMirror = _directMethods[action][method];
		if (methodMirror.parameters.isEmpty) {
			result = serviceMirror.invoke(methodMirror.simpleName, []);
		} else {
			result = serviceMirror.invoke(methodMirror.simpleName, data);
		}

		return result != null ? result.reflectee : null;
	}
}
