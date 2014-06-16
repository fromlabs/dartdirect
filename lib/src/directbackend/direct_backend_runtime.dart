part of directbackend;

final JSON_DATE_FORMAT = new DateFormat("yyyy/MM/dd HH:mm:ss");

class DirectHandler {

	static ProviderFunction<DirectManager> _DIRECT_MANAGER_SERVICE_PROVIDER = Registry.lookupProvider(DirectManager);

	final ScopeContext _isolateScopeContext;

	DirectHandler(this._isolateScopeContext);

	String get dartApi => _scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().dartApi);

	Future directCall(String base, String path, String json, DirectCallback callback) =>
		_scopedCall(() => _DIRECT_MANAGER_SERVICE_PROVIDER().directCall(base, path, json, callback));

	_scopedCall(ScopeRunnable runnable) {
		var result;
		var callScopeContext = Registry.initializeScope(DirectScopeContext.CALL, new MapScopeContext());
		try {
			result = Registry.runInScope(runnable, [_isolateScopeContext, callScopeContext]);
			if (result is Future) {
				return result.whenComplete(() => Registry.deinitializeScope(callScopeContext));
			} else {
				return result;
			}
		} finally {
			if (result is! Future) {
				Registry.deinitializeScope(callScopeContext);
			}
		}
	}
}