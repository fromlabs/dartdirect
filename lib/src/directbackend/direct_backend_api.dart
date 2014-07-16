part of directbackendapi;

// TODO potenziare annotazioni con gestione domini

String DIRECT_ENVIROMENT;

abstract class DirectModule extends RegistryModule {

	Type get transactionHandlerClazz;

	DirectManager directManager;

	@override
	Future configure(Map<String, dynamic> parameters) {
		return super.configure(parameters).then((_) {

			Logger.root.level = Level.ALL;
			Logger.root.onRecord.listen((LogRecord rec) {
				print('${rec.level.name}: ${rec.time}: ${rec.message}');
				if (rec.error != null) {
					print(rec.error);
					if (rec.stackTrace != null) {
						print(rec.stackTrace);
					}
				}
			});
			bindProviderFunction(Logger, Scope.ISOLATE, provideLogger);

			bindClass(TransactionHandler, Scope.ISOLATE, transactionHandlerClazz);

			this.directManager = new DirectManager(DIRECT_ENVIROMENT);
			bindInstance(DirectManager, this.directManager);
			bindClass(DirectHandler, Scope.ISOLATE);

			bindClass(DirectRequest, DirectScope.REQUEST);
		});
	}

	@override
	Future unconfigure() {
		this.directManager.deregisterAllDirectActions();
		this.directManager = null;
		return super.unconfigure();
	}

	Logger provideLogger() => new Logger("");

	void onBindingAdded(Type clazz) {
		var annotationMirror = reflect(DirectAction);
		if (reflectType(clazz).metadata.contains(annotationMirror)) {
			this.directManager.registerDirectAction(clazz);
		}
	}
}

typedef void DirectCallback(String jsonResponse, Map<String, List<String>> responseHeaders);

class DirectEnviroment {
	static const String CLIENT = "CLIENT";
	static const String SERVER = "SERVER";
}

const DirectAction = const _DirectAction();
const DirectMethod = const _DirectMethod();

class DirectParams {
}

class PagedList<T> {

	final List<T> data;

	final int total;

	PagedList(this.data, this.total);

	Map toJson() {
		return {
			"data": data,
			"total": total
		};
	}
}

abstract class MultipartRequest {

	Map<String, List<RequestParameter>> get parameters;

	RequestProgress get progress;

	Future get future;

	void onProgress(progressHandler(RequestProgress progress, bool closed));

	void onUploadParameter(parameterHandler(RequestParameter parameter));
}

abstract class RequestParameter {
	bool get isUpload;

	String get name;

	String get value;

	void onChunk(chunkHandler(List<int> chunk, bool closed));
}

abstract class RequestProgress {
	int get value;

	int get total;
}

class _DirectAction {
	const _DirectAction();
}

class _DirectMethod {
	const _DirectMethod();
}

abstract class DirectCall {
  Future onRequest(Future directCall(String base, String application, String path, String json, Map<String, List<String>> headers, MultipartRequest multipartRequest, DirectCallback callback));
}