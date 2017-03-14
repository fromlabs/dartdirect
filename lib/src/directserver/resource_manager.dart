part of dartdirect.server;

@injectable
class ResourceHandler {
  final String name;

  const ResourceHandler({this.name});
}

@injectable
class ResourceManager extends Loggable {

  Map<String, MethodDescriptor> _handlerMethods = {};

  Future resourceCall(String base, String application, String handlerName,
      HttpRequest request) async {
    if (!_handlerMethods.containsKey(handlerName)) {
      throw new ArgumentError(
          "Resource handler method not defined: $handlerName");
    }

    var methodDescriptor = _handlerMethods[handlerName];

    return Registry.invokeMethod(
        Registry.lookupObject(methodDescriptor.classDescriptor.type),
        methodDescriptor,
        [base, application, handlerName, request]);
  }

  void registerResourceHandler(Type clazz) {
    finest("Check if $clazz has a resource handler");

    var classDescriptor = Registry.getClass(clazz);

    if (classDescriptor != null) {
      var methodDescriptors =
        Registry.getAllMethodsAnnotatedWith(classDescriptor, ResourceHandler);

      if (methodDescriptors.isNotEmpty) {
        fine("Register resource handler class: $classDescriptor");

        for (var method in methodDescriptors) {
          fine("Register resource handler method: ${method}");

          for(var annotation in method.annotations) {
            if (annotation is ResourceHandler) {
              _handlerMethods[annotation.name] = method;
              break;
            }
          }
        }
      }
    }
  }

  void deregisterAllResourceHandlers() {
    fine("Deregister all resource handlers");

    _handlerMethods.clear();
  }
}