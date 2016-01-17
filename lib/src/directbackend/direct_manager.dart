part of directbackendapi;

const OnDirectRequestRegistered onDirectRequestRegistered =
    const OnDirectRequestRegistered();

@injectable
class OnDirectRequestRegistered {
  const OnDirectRequestRegistered();
}

class DirectScope extends Scope {
  static const Scope REQUEST = const Scope("DIRECT_REQUEST");

  const DirectScope(String id) : super(id);
}

class BusinessError extends Error {
  final String message;

  final bool forceCommit;

  final bool notifyToBackend;

  BusinessError(this.message,
      [this.forceCommit = false, this.notifyToBackend = false]);

  String get type => runtimeType.toString();

  String toString() => "$message [$type]";

  Map toJson() => {"type": type, "message": message};
}

abstract class DirectObject {
  String _application;

  String _action;

  String _method;

  String _type;

  num _tid;

  DirectObject(
      {String application, String action, String method, String type, num tid})
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

  Map toJson() => {
        "application": application,
        "action": _action,
        "method": _method,
        "type": _type,
        "tid": _tid
      };
}

@injectable
class DirectRequest extends DirectObject {
  List<dynamic> _data;

  Map<String, List<String>> _headers;

  Map<String, List<String>> _responseHeaders;

  Future _registerRequest(
      String application,
      String action,
      String method,
      String type,
      num tid,
      List<dynamic> data,
      MultipartRequest multipartRequest,
      Map<String, List<String>> headers) {
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

  Future _notifyDirectRequestRegisteredListeners() => Registry.notifyListeners(
      DirectScope.REQUEST, OnDirectRequestRegistered, false);
}

abstract class DirectResponse extends DirectObject {
  DirectResponse(DirectRequest directRequest, String type)
      : super(
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

  DirectResultResponse.throwBusinessError(
      DirectRequest directRequest, this.businessError)
      : this.result = {},
        super(directRequest, directRequest.type);

  bool get isNotifyError =>
      super.isNotifyError && businessError.notifyToBackend;

  get cause => businessError;

  Map toJson() => super.toJson()
    ..addAll(
        {"success": true, "result": result, "businessError": businessError});
}

class DirectErrorResponse extends DirectResponse {
  final String error;

  final cause;

  DirectErrorResponse(DirectRequest directRequest, this.cause, [this.error])
      : super(directRequest, "exception");

  Map toJson() => super.toJson()..addAll({"success": false, "error": error});
}

@injectable
abstract class TransactionHandler {
  Future openTransaction();

  Future commitTransaction();

  Future rollbackTransaction();
}

@injectable
abstract class RequestInterceptorHandler {
  Future requestBegin();
}

@injectable
class DirectManager {
  static Logger LOGGER = new Logger("directbackend.DirectManager");

  Map<String, Type> _directActions = {};
  Map<String, Map<String, MethodMirror>> _directMethods = {};

  final String enviroment;

  @Inject(TransactionHandler)
  Provider<TransactionHandler> TRANSACTION_HANDLER_PROVIDER;

  @Inject(RequestInterceptorHandler)
  Provider<RequestInterceptorHandler> REQUEST_INTERCEPTOR_HANDLER_PROVIDER;

  DirectManager(this.enviroment) {
    LOGGER.config("Direct Manager registered in $enviroment enviroment");
  }

  List getDirectMethodAnnotations(String directAction, String directMethod) {
    _checkDirectMethod(directAction, directMethod);

    var actionType = _directActions[directAction];

    return Registry.getMethodAnnotations(actionType, directMethod);
  }

  void registerDirectAction(Type clazz) {
    LOGGER.finest("Check if $clazz is a direct action");

    if (Registry.isTypeAnnotatedWith(clazz, DirectAction)) {
      var methods = Registry.getAllMethodsAnnotatedWith(clazz, DirectMethod);

      if (methods.isNotEmpty) {
        LOGGER.fine("Register direct action: $clazz");

        var actionMethodMap = {};
        for (var method in methods) {
          LOGGER.fine("Register direct method: ${method}");

          actionMethodMap[method.simpleName] = method;
        }

        var actionName = Registry.getSimpleName(clazz);
        _directActions[actionName] = clazz;
        _directMethods[actionName] = actionMethodMap;
      }
    }
  }

  void deregisterAllDirectActions() {
    LOGGER.fine("Deregister all direct actions");

    _directActions.clear();
    _directMethods.clear();
  }

  String get dartApi => _getDartApi(null, "embedded", true);

  Future directCall(DirectCall directCall) =>
      directCall.onRequest(directCallInternal);

  Future directCallInternal(
      String base,
      String application,
      String path,
      String json,
      Map<String, List<String>> headers,
      MultipartRequest multipartRequest,
      DirectCallback callback) {
    Completer completer = new Completer();
    Stopwatch watcher = new Stopwatch()..start();
    LOGGER.fine("Direct call...");

    if (path == "/direct/api") {
      callback(_getDartApi(base, application, false), {});

      completer.complete();
    } else {
      // read parameters
      var decodedDirectRequest = JSON.decode(json);

      DirectRequest directRequest = Registry.lookupObject(DirectRequest);
      bool transaction = !decodedDirectRequest["method"].startsWith("get") &&
          !decodedDirectRequest["method"].startsWith("is");

      directRequest
          ._registerRequest(
              application,
              decodedDirectRequest["action"],
              decodedDirectRequest["method"],
              decodedDirectRequest["type"],
              decodedDirectRequest["tid"],
              decodedDirectRequest["data"],
              multipartRequest,
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

        var jsonResponse = JSON.encode(directResponse);

        LOGGER.info(
            "Direct call ${directResponse.action}.${directResponse.method} elapsed in ${watcher.elapsedMilliseconds} ms");

        callback(jsonResponse, directRequest.responseHeaders);

        completer.complete();
      }).catchError((error, stacktrace) {
        DirectResponse directResponse;
        new Future.sync(() {
          if (error is BusinessError) {
            LOGGER.info("Business error", error, stacktrace);
            directResponse = new DirectResultResponse.throwBusinessError(
                directRequest, error);

            if (error.forceCommit) {
              if (transaction) {
                return _commitTransaction().catchError((error, stacktrace) {
                  LOGGER.severe("Commit error", error, stacktrace);
                  directResponse = new DirectErrorResponse(directRequest, error,
                      error.toString()); // error: "not_in_role","not_logged");
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

            directResponse = new DirectErrorResponse(directRequest, error,
                error.toString()); // error: "not_in_role","not_logged");
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

          var jsonResponse = JSON.encode(directResponse);

          LOGGER.info(
              "Direct call ${directResponse.action}.${directResponse.method} elapsed in ${watcher.elapsedMilliseconds} ms");

          callback(jsonResponse, {});

          completer.complete();
        });
      });
    }

    return completer.future;
  }

  Future _openTransaction() =>
      TRANSACTION_HANDLER_PROVIDER.get().openTransaction();

  Future _commitTransaction() =>
      TRANSACTION_HANDLER_PROVIDER.get().commitTransaction();

  Future _rollbackTransaction() =>
      TRANSACTION_HANDLER_PROVIDER.get().rollbackTransaction();

  Future _interceptRequestBegin() =>
      REQUEST_INTERCEPTOR_HANDLER_PROVIDER.get().requestBegin();

  String _getDartApi(String base, String application, bool localApi) {
    StringBuffer buffer = new StringBuffer();

    buffer.write("var remotingApi = ");

    buffer
      ..write(new JsonEncoder.withIndent("  ")
          .convert(_getDirectApiMap(base, application, localApi)))
      ..write(";")
      ..write("\r\n");

    buffer..write("onDirectApiLoaded(remotingApi);")..write("\r\n");
    return buffer.toString();
  }

  Map<String, dynamic> _getDirectApiMap(
      String base, String application, bool localApi) {
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

  void _checkDirectMethod(String directAction, String directMethod) {
    if (!_directActions.containsKey(directAction)) {
      throw new ArgumentError("Direct action not defined: $directAction");
    } else if (!_directMethods[directAction].containsKey(directMethod)) {
      throw new ArgumentError(
          "Direct method not defined: $directAction.$directMethod");
    }
  }

  _invokeDirectService(DirectRequest request) {
    _checkDirectMethod(request.action, request.method);

    var actionType = _directActions[request.action];
    return Registry.invokeMethod(
        Registry.lookupObject(actionType), request.method, request.data ?? []);
  }
}

@injectable
class DirectHandler {
  static Logger LOGGER = new Logger("directbackend.DirectHandler");

  // TODO verificare se possibile iniettarlo

  static ProvideFunction<DirectManager> _DIRECT_MANAGER_SERVICE_PROVIDE =
      Registry.lookupProvideFunction(DirectManager);

  Future<String> get dartApi =>
      _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDE().dartApi);

  Future directCall(DirectCall directCall) => _scopedCall(
      () => _DIRECT_MANAGER_SERVICE_PROVIDE().directCall(directCall));

  _scopedCall(ScopeRunnable runnable) =>
      Registry.runInScope(DirectScope.REQUEST, runnable);
}
