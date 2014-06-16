part of directbackendapi;

// TODO potenziare annotazioni con gestione domini

String DIRECT_ENVIROMENT;

class DirectScopeContext {
	static const RegistryScopeId CALL = const RegistryScopeId("CALL");
}

class DirectModule extends RegistryModule {

	DirectManager directManager;

	@override
	void configure(Map<String, dynamic> parameters) {
		super.configure(parameters);

		this.directManager = new DirectManager(DIRECT_ENVIROMENT);

		bindInstance(DirectManager, this.directManager);
		bindClass(DirectRequest, DirectScopeContext.CALL);
    	}

	@override
    	void unconfigure() {
		this.directManager.deregisterAllDirectActions();
		this.directManager = null;

		super.unconfigure();
	}

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

class _DirectAction {
	const _DirectAction();
}

class _DirectMethod {
	const _DirectMethod();
}

class DirectParams {
}

class PagedList<T> {

	final List<T> data;

	final int total;

	PagedList(this.data, this.total);

	Map toJson() {
		return {
			"data": data,
			"total": total,
			"success": true
		};
	}
}
