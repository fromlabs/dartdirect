part of directbackendapi;

class DirectScope extends Scope {

	static const Scope REQUEST = const Scope("DIRECT_REQUEST");

	const DirectScope(String id) : super(id);
}

class BusinessError extends Error {
	final String message;

	final bool forceCommit;

	final bool notifyToBackend;

	BusinessError(this.message, this.forceCommit, this.notifyToBackend);

	String toString() => message != null ? this.message : super.toString();

	Map toJson() => {
		"type": this.runtimeType.toString(),
		"message": message
	};
}

abstract class DirectObject {

	String _domain;

	String _action;

	String _method;

	String _type;

	num _tid;

	DirectObject({String domain, String action, String method, String type, num tid})
			: this._domain = domain,
			  this._action = action,
			  this._method = method,
			  this._type = type,
			  this._tid = tid;

	String get domain => _domain;

	String get action => _action;

	String get method => _method;

	String get type => _type;

	num get tid => _tid;

	Map toJson() => {
		"domain": domain,
		"action": _action,
		"method": _method,
		"type": _type,
		"tid": _tid
	};
}

class DirectRequest extends DirectObject {

	List<dynamic> _data;

	Map<String, List<String>> _headers;

	Map<String, List<String>> _responseHeaders;

	void _registerRequest(String domain, String action, String method, String type, num tid, List<dynamic> data, Map<String, List<String>> headers) {
		_domain = domain;
		_action = action;
		_method = method;
		_type = type;
		_tid = tid;
		_data = data;
		_headers = headers != null ? headers : const {};
		_responseHeaders = {};
	}

	List<dynamic> get data => _data;

	Map<String, List<String>> get headers => _headers;

	Map<String, List<String>> get responseHeaders => _responseHeaders;
}

abstract class DirectResponse extends DirectObject {

	DirectResponse(DirectRequest directRequest, String type) : super(domain: directRequest.domain, action: directRequest.action, method: directRequest.method, type: type, tid: directRequest.tid);

	bool get isNotifyError => cause != null;

	get cause => null;
}

class DirectResultResponse extends DirectResponse {

	final result;

	final bool locked;

	final Map<String, dynamic> notifications;

	final BusinessError businessError;

	DirectResultResponse(DirectRequest directRequest, this.result, [this.locked = false, this.notifications = const {}])
			: this.businessError = null,
			  super(directRequest, directRequest.type);

	DirectResultResponse.throwBusinessError(DirectRequest directRequest, this.businessError)
			: this.result = {},
			  this.locked = false,
			  this.notifications = {},
			  super(directRequest, directRequest.type);

	bool get isNotifyError => super.isNotifyError && businessError.notifyToBackend;

	get cause => businessError;

	Map toJson() => super.toJson()..addAll({
				"success": true,
				"result": result,
				"businessError": businessError,
				"locked": locked,
				"notifications": notifications
			});
}

class DirectErrorResponse extends DirectResponse {

	final String error;

	final cause;

	DirectErrorResponse(DirectRequest directRequest, this.cause, [this.error]) : super(directRequest, "exception");

	Map toJson() => super.toJson()..addAll({
				"success": false,
				"error": error
			});
}

abstract class TransactionHandler {

	Future openTransaction();

	Future commitTransaction();

	Future rollbackTransaction();
}

class DirectManager {
	static Logger LOGGER = new Logger(MirrorSystem.getName(reflectType(DirectManager).simpleName));

	Map<String, Type> _directActions = {};
	Map<String, Map<String, MethodMirror>> _directMethods = {};

	final String enviroment;

	@Inject
	Provider<TransactionHandler> _TRANSACTION_HANDLER_PROVIDER;

	DirectManager(this.enviroment) {
		LOGGER.config("Direct Manager registered in $enviroment enviroment");
	}

	void registerDirectAction(Type actionClazz) {
		LOGGER.config("Register direct action: $actionClazz");

		// recupero metodi
		Map<String, MethodMirror> methods = new Map<String, MethodMirror>();
		var annotationMirror = reflect(DirectMethod);
		reflectClass(actionClazz).declarations.forEach((methodSymbol, methodMirror) {
			if (methodMirror is MethodMirror && methodMirror.metadata.contains(annotationMirror)) {
				var name = MirrorSystem.getName(methodSymbol);
				LOGGER.config("Register direct method: ${name}");

				methods[name] = methodMirror;
			}
		});

		var actionName = actionClazz.toString();
		_directActions[actionName] = actionClazz;
		_directMethods[actionName] = methods;
	}

	void deregisterAllDirectActions() {
		LOGGER.config("Deregister all direct actions");

		_directActions.clear();
		_directMethods.clear();
	}

	String get dartApi => _getDartApi(null, null, true);

	Future directCall(String base, String path, String json, Map<String, List<String>> headers, DirectCallback callback) {
		Completer completer = new Completer();

		if (path.endsWith("/direct/api")) {
			var domain = path != "/direct/api" ? path.substring(1, path.length - "/direct/api".length) : "";

			callback(_getDartApi(base, domain, false), {});

			completer.complete();
		} else if (path.endsWith("/direct")) {
			var domain = path != "/direct" ? path.substring(1, path.length - "/direct".length) : "";

			// read parameters
			var decodedDirectRequest = JSON.decode(json);
			DirectRequest directRequest = Registry.lookupObject(DirectRequest);
			directRequest._registerRequest(domain, decodedDirectRequest["action"], decodedDirectRequest["method"], decodedDirectRequest["type"], decodedDirectRequest["tid"], decodedDirectRequest["data"], headers);

			bool transaction = !directRequest.action.startsWith("get") && !directRequest.action.startsWith("is");
			new Future.sync(() {
				if (transaction) {
					return _openTransaction();
				}
			}).then((_) => _invokeDirectService(directRequest)).then((value) {
				if (transaction) {
					return _commitTransaction().then((_) => value);
				} else {
					return value;
				}
			}).then((value) {
				var directResponse = new DirectResultResponse(directRequest, value);

				callback(JSON.encode(directResponse), directRequest.responseHeaders);

				completer.complete();
			}).catchError((error) {
				DirectResponse directResponse;
				new Future.sync(() {
					if (error is BusinessError) {
						directResponse = new DirectResultResponse.throwBusinessError(directRequest, error);

						if (error.forceCommit) {
							if (transaction) {
								return _commitTransaction();
							}
						} else {
							if (transaction) {
								return _rollbackTransaction();
							}
						}
					} else {
						directResponse = new DirectErrorResponse(directRequest, error); // error: "not_in_role","not_logged");
						if (transaction) {
							return _rollbackTransaction();
						}
					}
				}).then((_) {
					if (directResponse.isNotifyError) {
						// TODO log errore
					}

					callback(JSON.encode(directResponse), {});

					completer.complete();
				});
			});
		} else {
			completer.completeError("Path not valid: $path");
		}

		return completer.future;
	}

	Future _openTransaction() => _TRANSACTION_HANDLER_PROVIDER.get().openTransaction();

	Future _commitTransaction() => _TRANSACTION_HANDLER_PROVIDER.get().commitTransaction();

	Future _rollbackTransaction() => _TRANSACTION_HANDLER_PROVIDER.get().rollbackTransaction();

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

	_invokeDirectService(DirectRequest request) {
		InstanceMirror result;
		var actionType = _directActions[request.action];
		var service = Registry.lookupObject(actionType);
		var serviceMirror = reflect(service);
		MethodMirror methodMirror = _directMethods[request.action][request.method];
		if (methodMirror.parameters.isEmpty) {
			result = serviceMirror.invoke(methodMirror.simpleName, []);
		} else {
			result = serviceMirror.invoke(methodMirror.simpleName, request.data);
		}

		return result != null ? result.reflectee : null;
	}
}

class DirectHandler {

	static ProviderFunction<DirectManager> _DIRECT_MANAGER_SERVICE_PROVIDER = Registry.lookupProviderFunction(DirectManager);

	Future<String> get dartApi => _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().dartApi);

	Future directCall(String base, String path, String json, Map<String, List<String>> headers, DirectCallback callback) => _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().directCall(base, path, json, headers, callback));

	_scopedCall(ScopeRunnable runnable) => Registry.runInScope(DirectScope.REQUEST, runnable);
}
