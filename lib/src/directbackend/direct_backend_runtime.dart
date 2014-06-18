part of directbackend;

final JSON_DATE_FORMAT = new DateFormat("yyyy/MM/dd HH:mm:ss");

class DirectHandler {

	static ProviderFunction<DirectManager> _DIRECT_MANAGER_SERVICE_PROVIDER = Registry.lookupProviderFunction(DirectManager);

	final ScopeContext _isolateScopeContext;

	DirectHandler(this._isolateScopeContext);

	Future<String> get dartApi => _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().dartApi);

	Future directCall(String base, String path, String json, DirectCallback callback) => _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().directCall(base, path, json, callback));

	_scopedCall(ScopeRunnable runnable) {
		var callScopeContext;
		return Registry.initializeScope(DirectScopeContext.CALL, new MapScopeContext())
		.then((context) => callScopeContext = context)
		.then((_) => Registry.runInScope(runnable, [_isolateScopeContext, callScopeContext]))
		.whenComplete(() => Registry.deinitializeScope(callScopeContext));
	}
}
