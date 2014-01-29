part of directbackend;

final JSON_DATE_FORMAT = new DateFormat("yyyy/MM/dd HH:mm:ss");

typedef void DirectCallback(String jsonResponse);

class DirectHandler {

  String get dartApi =>
      _getDartApi(null, true);

	void directCall(String base, String path, String json, DirectCallback callback) {
	  print("${DIRECT_ENVIROMENT == DirectEnviroment.CLIENT ? "Local" : "Remote"} call to '$path'");

		if (path == "/direct/api") {
	    callback(_getDartApi(base, false));
		} else {
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

	 		var result = _invokeDirectService(action, method, directRequest["data"]);

      if (result is! Future) {
        result = new Future.value(result);
      }

      result.then((value) {
        directResponse["result"] = value;

        callback(JSON.encode(directResponse));
      });
		}
	}

  String _getDartApi(String base, bool localApi) {
    StringBuffer buffer = new StringBuffer();
    buffer
      ..write("Ext.ns('Ext.app');")
      ..write("\r\n");

    buffer.write("Ext.app.REMOTING_API = ");

    buffer
      ..write(JSON.encode(_getDirectApiMap(base, localApi)))
      ..write(";")
      ..write("\r\n");

    buffer
      ..write("onDirectApiLoaded(Ext.app.REMOTING_API);")
      ..write("\r\n");
    return buffer.toString();
  }

  Map<String, dynamic> _getDirectApiMap(String base, bool localApi) {
    Map<String, dynamic> apiMap = {};

    apiMap["url"] = base != null ? "$base/direct" : "direct";
    apiMap["type"] = localApi ? "dart" : "remoting";
    apiMap["maxRetries"] = "0";
    apiMap["timeout"] = "300000"; // 5 minuti
    apiMap["enableBuffer"] = false;

    Map<String, dynamic> actionMap = {};
    apiMap["actions"] = actionMap;

    List<Object> methodList;
    Map<String, Object> methodMap;

    currentMirrorSystem().libraries.forEach((uri, libraryMirror) {
      if (!uri.toString().startsWith("dart:")) {
        libraryMirror.declarations.forEach((symbol, declarationMirror) {

          var directActionMetadata = declarationMirror.metadata.firstWhere(
              (m) => m.reflectee is DirectAction, orElse: () => null);
          if(declarationMirror is ClassMirror && directActionMetadata != null) {
            methodList = [];
            actionMap[MirrorSystem.getName(symbol)] = methodList;
            declarationMirror.declarations.forEach((methodSymbol, declarationMirror2) {
              if (declarationMirror2 is MethodMirror && declarationMirror2.metadata.contains(reflect(DirectMethod))) {
                methodMap = {};
                methodList.add(methodMap);
                methodMap["name"] = MirrorSystem.getName(methodSymbol);
                methodMap["len"] = declarationMirror2.parameters.length;
              }
            });
          }
        });
      }
    });

    return apiMap;
  }

	_invokeDirectService(String action, String method, List<dynamic> data) {
	  InstanceMirror result;
	  currentMirrorSystem().libraries.forEach((uri, libraryMirror) {
	    if (!uri.toString().startsWith("dart:")) {
	      var typeMirror = libraryMirror.declarations[new Symbol(action)];
	      if(typeMirror is ClassMirror && typeMirror.metadata.firstWhere((m) => m.reflectee is DirectAction, orElse: () => null) != null) {
          var serviceMirror = typeMirror.newInstance(new Symbol(""), []);
          var methodSymbol = new Symbol(method);
          MethodMirror methodMirror = serviceMirror.type.declarations[methodSymbol];
          if (methodMirror != null && methodMirror.metadata.contains(reflect(DirectMethod))) {
            if (methodMirror.parameters.isEmpty) {
              result = serviceMirror.invoke(methodSymbol, []);
            } else {
              result = serviceMirror.invoke(methodSymbol, data);
            }
          }
          return;
        }
	    }
	  });
	  return result != null ? result.reflectee : null;
	}
}