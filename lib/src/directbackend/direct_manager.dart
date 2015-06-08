part of directbackendapi;

const Object OnDirectRequestRegistered = const _OnDirectRequestRegistered();

class _OnDirectRequestRegistered {
  const _OnDirectRequestRegistered();
}

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

  Map toJson() => {"type": this.runtimeType.toString(), "message": message};
}

abstract class DirectObject {
  String _application;

  String _action;

  String _method;

  String _type;

  num _tid;

  DirectObject({String application, String action, String method, String type, num tid})
      : this._application = application,
        this._action = action,
        this._method = method,
        this._type = type,
        this._tid = tid;

  String get application => _application;

  String get action => _action;

  String get method => _method;

  String get type => _type;

  num get tid => _tid;

  Map toJson() => {"application": application, "action": _action, "method": _method, "type": _type, "tid": _tid};
}

class DirectRequest extends DirectObject {
  List<dynamic> _data;

  Map<String, List<String>> _headers;

  Map<String, List<String>> _responseHeaders;

  Future _registerRequest(String application, String action, String method, String type, num tid, List<dynamic> data,
      MultipartRequest multipartRequest, Map<String, List<String>> headers) {
    _application = application;
    _action = action;
    _method = method;
    _type = type;
    _tid = tid;
    if (multipartRequest != null) {
      _data = [multipartRequest];
    } else {
      _data = data;
    }
    _headers = headers != null ? headers : const {};
    _responseHeaders = {};

    return _notifyDirectRequestRegisteredListeners();
  }

  List<dynamic> get data => _data;

  Map<String, List<String>> get headers => _headers;

  String getHeaderString(String name) {
    var values = headers[name];
    if (values != null) {
      if (values.isNotEmpty) {
        if (values[0] != null && values[0].isNotEmpty) {
          return values[0];
        }
      }
    }
    return null;
  }

  num getHeaderNumber(String name) {
    var s = getHeaderString(name);
    return s != null ? num.parse(s) : null;
  }

  Map<String, List<String>> get responseHeaders => _responseHeaders;

  Future onDirectRequestRegisteredInternal() => new Future.value();

  Future _notifyDirectRequestRegisteredListeners() =>
      Registry.notifyListeners(DirectScope.REQUEST, OnDirectRequestRegistered, false);
}

abstract class DirectResponse extends DirectObject {
  DirectResponse(DirectRequest directRequest, String type) : super(
          application: directRequest.application,
          action: directRequest.action,
          method: directRequest.method,
          type: type,
          tid: directRequest.tid);

  bool get isNotifyError => cause != null;

  get cause => null;
}

class DirectResultResponse extends DirectResponse {
  final result;

  final BusinessError businessError;

  DirectResultResponse(DirectRequest directRequest, this.result)
      : this.businessError = null,
        super(directRequest, directRequest.type);

  DirectResultResponse.throwBusinessError(DirectRequest directRequest, this.businessError)
      : this.result = {},
        super(directRequest, directRequest.type);

  bool get isNotifyError => super.isNotifyError && businessError.notifyToBackend;

  get cause => businessError;

  Map toJson() => super.toJson()..addAll({"success": true, "result": result, "businessError": businessError});
}

class DirectErrorResponse extends DirectResponse {
  final String error;

  final cause;

  DirectErrorResponse(DirectRequest directRequest, this.cause, [this.error]) : super(directRequest, "exception");

  Map toJson() => super.toJson()..addAll({"success": false, "error": error});
}

abstract class TransactionHandler {
  Future openTransaction();

  Future commitTransaction();

  Future rollbackTransaction();
}

abstract class RequestInterceptorHandler {
  Future requestBegin();
}

class DirectManager {
  static Logger LOGGER = new Logger("directbackend.DirectManager");

  Map<String, Type> _directActions = {};
  Map<String, Map<String, MethodMirror>> _directMethods = {};

  final String enviroment;

  @Inject
  Provider<TransactionHandler> _TRANSACTION_HANDLER_PROVIDER;

  @Inject
  Provider<RequestInterceptorHandler> _REQUEST_INTERCEPTOR_HANDLER_PROVIDER;

  DirectManager(this.enviroment) {
    LOGGER.config("Direct Manager registered in $enviroment enviroment");
  }

  void registerDirectAction(Type actionClazz) {
    LOGGER.fine("Register direct action: $actionClazz");

    // recupero metodi
    Map<String, MethodMirror> methods = new Map<String, MethodMirror>();
    var annotationMirror = reflect(DirectMethod);
    reflectClass(actionClazz).declarations.forEach((methodSymbol, methodMirror) {
      if (methodMirror is MethodMirror && methodMirror.metadata.contains(annotationMirror)) {
        var name = MirrorSystem.getName(methodSymbol);
        LOGGER.fine("Register direct method: ${name}");

        methods[name] = methodMirror;
      }
    });

    var actionName = actionClazz.toString();
    _directActions[actionName] = actionClazz;
    _directMethods[actionName] = methods;
  }

  void deregisterAllDirectActions() {
    LOGGER.fine("Deregister all direct actions");

    _directActions.clear();
    _directMethods.clear();
  }

  String get dartApi => _getDartApi(null, null, true);

  Future directCall(DirectCall directCall) => directCall.onRequest(directCallInternal);

  Future directCallInternal(String base, String application, String path, String json,
      Map<String, List<String>> headers, MultipartRequest multipartRequest, DirectCallback callback) {
    Completer completer = new Completer();

    if (path == "/direct/api") {
      callback(_getDartApi(base, application, false), {});

      completer.complete();
    } else {
      // read parameters
      var decodedDirectRequest = JSON.decode(json);
      DirectRequest directRequest = Registry.lookupObject(DirectRequest);
      bool transaction =
          !decodedDirectRequest["action"].startsWith("get") && !decodedDirectRequest["action"].startsWith("is");
      directRequest
          ._registerRequest(application, decodedDirectRequest["action"], decodedDirectRequest["method"],
              decodedDirectRequest["type"], decodedDirectRequest["tid"], decodedDirectRequest["data"], multipartRequest,
              headers)
          .then((_) {
        return _interceptRequestBegin().then((_) {
          if (transaction) {
            return _openTransaction();
          }
        });
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
      }).catchError((error, stacktrace) {
        DirectResponse directResponse;
        new Future.sync(() {
          if (error is BusinessError) {
            LOGGER.info("Business error", error, stacktrace);
            directResponse = new DirectResultResponse.throwBusinessError(directRequest, error);

            if (error.forceCommit) {
              if (transaction) {
                return _commitTransaction().catchError((error, stacktrace) {
                  LOGGER.severe("Commit error", error, stacktrace);
                  directResponse = new DirectErrorResponse(directRequest, error); // error: "not_in_role","not_logged");
                });
              }
            } else {
              if (transaction) {
                return _rollbackTransaction().catchError((error, stacktrace) {
                  LOGGER.severe("Rollback error", error, stacktrace);
                });
              }
            }
          } else {
            LOGGER.severe("System error", error, stacktrace);

            directResponse = new DirectErrorResponse(directRequest, error); // error: "not_in_role","not_logged");
            if (transaction) {
              return _rollbackTransaction().catchError((error, stacktrace) {
                LOGGER.severe("Rollback error", error, stacktrace);
              });
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
    }

    return completer.future;
  }

  Future _openTransaction() => _TRANSACTION_HANDLER_PROVIDER.get().openTransaction();

  Future _commitTransaction() => _TRANSACTION_HANDLER_PROVIDER.get().commitTransaction();

  Future _rollbackTransaction() => _TRANSACTION_HANDLER_PROVIDER.get().rollbackTransaction();

  Future _interceptRequestBegin() => _REQUEST_INTERCEPTOR_HANDLER_PROVIDER.get().requestBegin();

  String _getDartApi(String base, String application, bool localApi) {
    StringBuffer buffer = new StringBuffer();

    buffer.write("var remotingApi = ");

    buffer
      ..write(new JsonEncoder.withIndent("  ").convert(_getDirectApiMap(base, application, localApi)))
      ..write(";")
      ..write("\r\n");

    buffer
      ..write("onDirectApiLoaded(remotingApi);")
      ..write("\r\n");
    return buffer.toString();
  }

  Map<String, dynamic> _getDirectApiMap(String base, String application, bool localApi) {
    Map<String, dynamic> apiMap = {};

    StringBuffer url = new StringBuffer();
    if (base != null) {
      url.write("$base/");
    }
    url.write("direct");

    apiMap["application"] = application;
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
    if (actionType == null) {
      throw new ArgumentError("Direct action not defined: ${request.action}");
    }
    var service = Registry.lookupObject(actionType);
    var serviceMirror = reflect(service);
    MethodMirror methodMirror = _directMethods[request.action][request.method];
    if (methodMirror == null) {
      throw new ArgumentError("Direct method not defined: ${request.action}.${request.method}");
    } else if (methodMirror.parameters.isEmpty) {
      result = serviceMirror.invoke(methodMirror.simpleName, []);
    } else {
      result = serviceMirror.invoke(methodMirror.simpleName, request.data);
    }

    return result != null ? result.reflectee : null;
  }
}

class DirectHandler {
  static Logger LOGGER = new Logger("directbackend.DirectHandler");

  static ProviderFunction<DirectManager> _DIRECT_MANAGER_SERVICE_PROVIDER =
      Registry.lookupProviderFunction(DirectManager);

  Future<String> get dartApi => _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().dartApi);

  Future directCall(DirectCall directCall) {
    Stopwatch watcher = new Stopwatch()..start();
    LOGGER.info("Direct call...");

    return _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().directCall(directCall)).whenComplete(() {
      LOGGER.info("Direct call elapsed in ${watcher.elapsedMilliseconds} ms");
    });
  }

  _scopedCall(ScopeRunnable runnable) => Registry.runInScope(DirectScope.REQUEST, runnable);
}
