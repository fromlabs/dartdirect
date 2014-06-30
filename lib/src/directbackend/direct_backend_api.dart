part of directbackendapi;

// TODO potenziare annotazioni con gestione domini

String DIRECT_ENVIROMENT;

class DirectModule extends RegistryModule {

	DirectManager directManager;

	@override
	Future configure(Map<String, dynamic> parameters) {
		return super.configure(parameters).then((_) {

			this.directManager = new DirectManager(DIRECT_ENVIROMENT);

			Logger.root.level = Level.ALL;
			Logger.root.onRecord.listen((LogRecord rec) {
				print('${rec.level.name}: ${rec.time}: ${rec.message}');
			});
			bindProviderFunction(Logger, Scope.ISOLATE, provideLogger);

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

typedef void DirectCallback(String jsonResponse);

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

class _DirectAction {
	const _DirectAction();
}

class _DirectMethod {
	const _DirectMethod();
}
