part of directregistry;

typedef T ProviderFunction<T>();

class FutureInstance<T> {

	final Future<T> future;

	final T lazyInstance;

	FutureInstance(T lazyInstance)
			: this.lazyInstance = lazyInstance,
			  this.future = new Future.value(lazyInstance);
}

abstract class ScopeBindingListener {
	void postBind();
	void preUnbind();
}

abstract class Provider<T> {
	T provide();
}

abstract class ProviderListener<T> {

	void postBind(T instance);

	void preUnbind(T instance);
}

abstract class AsyncProviderListener<T> {

	void postBind(T instance);

	void preUnbind(T instance);
}

class _ToFunctionProvider<T> extends Provider<T> {

	final ProviderFunction<T> _function;

	_ToFunctionProvider(this._function);

	T provide() => _function();
}

class _ToClassProvider<T> extends Provider<T> {

	final Type _clazz;

	_ToClassProvider(this._clazz);

	T provide() => _newInstanceFromClass(this._clazz);
}

class _ToInstanceProvider<T> extends Provider<T> {

	final T _instance;

	_ToInstanceProvider(this._instance);

	T provide() => this._instance;
}

typedef ScopeRunnable();

class _ProviderBinding {

	final Type clazz;

	final RegistryScopeId scope;

	final Provider provider;

	_ProviderBinding(this.clazz, this.scope, this.provider);
}

abstract class RegistryModule {

	Map<Type, _ProviderBinding> _bindings;

	void configure(Map<String, dynamic> parameters) {
		_bindings = new LinkedHashMap.identity();
	}

	void unconfigure() {
		_bindings.clear();
		_bindings = null;
	}

	void bindInstance(Type clazz, instance) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, ScopeContext.ISOLATE, new _ToInstanceProvider(instance)));
	}

	void bindClass(Type clazz, RegistryScopeId scope, [Type clazzImpl]) {
		clazzImpl = clazzImpl != null ? clazzImpl : clazz;
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, new _ToClassProvider(clazzImpl)));
	}

	void bindProviderFunction(Type clazz, RegistryScopeId scope, ProviderFunction providerFunction) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, new _ToFunctionProvider(providerFunction)));
	}

	void bindProvider(Type clazz, RegistryScopeId scope, Provider provider) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, provider));
	}

	void _addProviderBinding(Type clazz, _ProviderBinding binding) {
		_bindings[clazz] = binding;

		onBindingAdded(clazz);
	}

	void onBindingAdded(Type clazz) {}

	_ProviderBinding _getProviderBinding(Type clazz) => _bindings[clazz];
}

class RegistryScopeId {

	final String id;

	const RegistryScopeId(this.id);

	String toString() => this.id;
}

abstract class ScopeContext {
	static const RegistryScopeId NONE = const RegistryScopeId("NONE");
	static const RegistryScopeId ISOLATE = const RegistryScopeId("ISOLATE");

	RegistryScopeId _scope;

	void _registerInScope(RegistryScopeId scope) {
		this._scope = scope;
	}

	void _deregisterFromScope() {
		this._scope = null;
	}

	Map<Provider, dynamic> get bindings;

	void set bindings(Map<Provider, dynamic> providers);

	void removeBindings();
}

class MapScopeContext extends ScopeContext {

	Map<Provider, dynamic> _bindings;

	@override
	Map<Provider, dynamic> get bindings => _bindings;

	@override
	void set bindings(Map<Provider, dynamic> bindings) {
		_bindings = bindings;
	}

	@override
	void removeBindings() {
		_bindings = null;
	}
}

class Registry {

	static const _SCOPE_CONTEXTS = "_SCOPE_CONTEXTS";

	static RegistryModule _MODULE;

	static Map<Type, ProviderFunction> _SCOPED_PROVIDERS_CACHE;

	static void load(Type moduleClazz, Map<String, dynamic> parameters) {
		print("Load module");

		var module = _newInstanceFromClass(moduleClazz);
		if (module is! RegistryModule) {
			throw new ArgumentError("$moduleClazz is not a registry module");
		}
		_MODULE = module;

		_SCOPED_PROVIDERS_CACHE = new HashMap.identity();
		_MODULE.configure(parameters);

		_injectProviders();
	}

	static void unload() {
		print("Unload module");

		_MODULE.unconfigure();
		_MODULE = null;
		_SCOPED_PROVIDERS_CACHE = null;
	}

	static ScopeContext initializeScope(RegistryScopeId scope, ScopeContext scopeContext) {
		print("Initialize scope: $scope");

		Map<Provider, dynamic> providers = scopeContext.bindings;
		if (providers == null) {
			providers = new LinkedHashMap.identity();
			scopeContext.bindings = providers;
		} else {
			providers.clear();
		}

		scopeContext._registerInScope(scope);

		return scopeContext;
	}

	static void deinitializeScope(ScopeContext scopeContext) {
		print("Deinitialize scope: ${scopeContext._scope}");

		Map<Provider, dynamic> providers = scopeContext.bindings;
		providers.forEach((provider, instance) {
			if (instance is ScopeBindingListener) {
				instance.preUnbind();
			}

			if (provider is ProviderListener) {
				(provider as ProviderListener).preUnbind(instance);
			}

			if (provider is AsyncProviderListener) {
				if (instance is FutureInstance) {
					(provider as AsyncProviderListener).preUnbind(instance.lazyInstance);
				} else if (instance is Future) {
					instance.then((lazyInstance) {
						(provider as AsyncProviderListener).preUnbind(lazyInstance);
					});
				}
			}
		});

		providers.clear();
		scopeContext.removeBindings();

		scopeContext._deregisterFromScope();
	}

	static runInScope(ScopeRunnable runnable, List<ScopeContext> scopeContexts) {
		return runZoned(() {
			return runnable();
		}, zoneValues: {
			_SCOPE_CONTEXTS: scopeContexts
		}, onError: (error) {
			print(error);
			if (error is Error) {
				print(error.stackTrace);
			}
		});
	}

	static lookupObject(Type clazz) {
		ProviderFunction provider = lookupProvider(clazz);
		if (provider != null) {
			return provider();
		} else {
			print("Provider not found: $clazz");

			return null;
		}
	}

	static ProviderFunction lookupProvider(Type clazz) {
		_ProviderBinding providerBinding = _MODULE._getProviderBinding(clazz);
		if (providerBinding != null) {
			ProviderFunction scopedProvider = _SCOPED_PROVIDERS_CACHE[clazz];
			if (scopedProvider == null) {
				scopedProvider = () {
					if (providerBinding.scope != ScopeContext.NONE) {
						ScopeContext scopeContext = _getScopeContext(providerBinding.scope);
						if (scopeContext != null) {
							return _provideInScope(providerBinding.provider, scopeContext);
						} else {
							print("Scope context not found for provider binding: $clazz");

							return null;
						}
					} else {
						return providerBinding.provider.provide();
					}
				};

				_SCOPED_PROVIDERS_CACHE[clazz] = scopedProvider;
			}

			return scopedProvider;
		} else {
			print("Provider binding not found: $clazz");

			return null;
		}
	}

	static _provideInScope(Provider provider, ScopeContext scopeContext) {
		Map<Provider, dynamic> providers = scopeContext.bindings;

		var instance = providers[provider];
		bool newInstance = (instance == null);

		if (newInstance) {
			instance = provider.provide();

			providers[provider] = instance;

			_injectBindings(instance);

			if (instance is ScopeBindingListener) {
				instance.postBind();
			}

			if (provider is ProviderListener) {
				(provider as ProviderListener).postBind(instance);
			}

			if (provider is AsyncProviderListener && instance is Future) {
				instance.then((lazyInstance) {
					instance = new FutureInstance(lazyInstance);

					providers[provider] = instance;

					_injectBindings(instance);

					if (instance is ScopeBindingListener) {
						instance.postBind();
					}

					(provider as AsyncProviderListener).postBind(lazyInstance);
				});
			}
		}

		return instance is FutureInstance ? instance.future : instance;
	}

	static ScopeContext _getScopeContext(RegistryScopeId scope) {
		List<ScopeContext> scopeContexts = Zone.current[_SCOPE_CONTEXTS];

		var found;
		if (scopeContexts != null) {
			found = scopeContexts.firstWhere((scopeContext) => scopeContext != null && scopeContext._scope == scope, orElse: () => null);
		}

		if (found != null) {
			return found;
		} else {
			print("Scope context not found for scope: $scope");

			return null;
		}
	}

	static void _injectProviders() {
		_MODULE._bindings.values.forEach((providerBinding) => _injectBindings(providerBinding.provider));
	}

	static void _injectBindings(instance) {
		// TODO injection
	}
}

_newInstanceFromClass(Type clazz) {
	ClassMirror mirror = reflectClass(clazz);
	var object = mirror.newInstance(MirrorSystem.getSymbol(""), []);
	return object.reflectee;
}
