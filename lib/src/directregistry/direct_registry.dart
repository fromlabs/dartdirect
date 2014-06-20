part of directregistry;

const Object Inject = const _Inject();

typedef T ProviderFunction<T>();

abstract class Provider<T> {
	T get();
}

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

abstract class ProviderListener<T> {

	void postBind(T instance);

	void preUnbind(T instance);
}

abstract class AsyncProviderListener<T> {

	void postBind(T instance);

	void preUnbind(T instance);
}

class _Inject {
	const _Inject();
}

class _ToFunctionProvider<T> extends Provider<T> {

	final ProviderFunction<T> _function;

	_ToFunctionProvider(this._function);

	T get() => _function();
}

class _ToClassProvider<T> extends Provider<T> {

	final Type _clazz;

	_ToClassProvider(this._clazz);

	T get() => _newInstanceFromClass(this._clazz);
}

class _ToInstanceProvider<T> extends Provider<T> {

	final T _instance;

	_ToInstanceProvider(this._instance);

	T get() => this._instance;
}

typedef ScopeRunnable();

class _ProviderBinding {

	final Type clazz;

	final ScopeContextId scope;

	final Provider provider;

	_ProviderBinding(this.clazz, this.scope, this.provider);
}

abstract class RegistryModule {

	Map<Type, _ProviderBinding> _bindings;

	Future configure(Map<String, dynamic> parameters) {
		_bindings = {};

		return new Future.value();
	}

	Future unconfigure() {
		_bindings.clear();
		_bindings = null;

		return new Future.value();
	}

	void bindInstance(Type clazz, instance) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, ScopeContext.ISOLATE, new _ToInstanceProvider(instance)));
	}

	void bindClass(Type clazz, ScopeContextId scope, [Type clazzImpl]) {
		clazzImpl = clazzImpl != null ? clazzImpl : clazz;
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, new _ToClassProvider(clazzImpl)));
	}

	void bindProviderFunction(Type clazz, ScopeContextId scope, ProviderFunction providerFunction) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, new _ToFunctionProvider(providerFunction)));
	}

	void bindProvider(Type clazz, ScopeContextId scope, Provider provider) {
		_addProviderBinding(clazz, new _ProviderBinding(clazz, scope, provider));
	}

	void _addProviderBinding(Type clazz, _ProviderBinding binding) {
		_bindings[clazz] = binding;

		onBindingAdded(clazz);
	}

	void onBindingAdded(Type clazz) {}

	_getProviderBinding(Type clazz) =>_bindings[clazz];
}

class ScopeContextId {

	final String id;

	const ScopeContextId(this.id);

	String toString() => this.id;
}

abstract class ScopeContext {
	static const ScopeContextId NONE = const ScopeContextId("NONE");
	static const ScopeContextId ISOLATE = const ScopeContextId("ISOLATE");

	ScopeContextId _scope;

	void _registerInScope(ScopeContextId scope) {
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

	static Future load(Type moduleClazz, [Map<String, dynamic> parameters = const {}]) {
		print("Load module");

		var module = _newInstanceFromClass(moduleClazz);
		if (module is! RegistryModule) {
			throw new ArgumentError("$moduleClazz is not a registry module");
		}
		_MODULE = module;

		_SCOPED_PROVIDERS_CACHE = {};
		return _MODULE.configure(parameters).then((_) {
			_injectProviders();
		});
	}

	static Future unload() {
		print("Unload module");

		return _MODULE.unconfigure().then((_) {
			_MODULE = null;
			_SCOPED_PROVIDERS_CACHE = null;
		});
	}

	static Future<ScopeContext> initializeScope(ScopeContextId scope, ScopeContext scopeContext) {
		print("Initialize scope: $scope");

		Map<Provider, dynamic> providers = scopeContext.bindings;
		if (providers == null) {
			providers = {};
			scopeContext.bindings = providers;
		} else {
			providers.clear();
		}

		scopeContext._registerInScope(scope);

		return new Future.value(scopeContext);
	}

	static Future deinitializeScope(ScopeContext scopeContext) {
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

		return new Future.value();
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
		ProviderFunction provider = lookupProviderFunction(clazz);
		if (provider != null) {
			return provider();
		} else {
			print("Provider not found: $clazz");

			return null;
		}
	}

	static lookupProvider(Type clazz) {
		ProviderFunction provider = lookupProviderFunction(clazz);
		if (provider != null) {
			return new _ToFunctionProvider(provider);
		} else {
			print("Provider not found: $clazz");

			return null;
		}
	}

	static ProviderFunction lookupProviderFunction(Type clazz) {
		if (_MODULE == null) {
			throw new StateError("Registry module not loaded");
		}

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
						return providerBinding.provider.get();
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
			instance = provider.get();

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

	static ScopeContext _getScopeContext(ScopeContextId scope) {
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
		reflect(instance).type.declarations.forEach((symbol, DeclarationMirror mirror) {
			if (mirror is VariableMirror) {
				if (mirror.metadata.contains(reflect(Inject))) {
					var variableType = mirror.type;
					if (variableType is ClassMirror && variableType.isSubclassOf(reflectClass(Provider))) {
						if (variableType.typeArguments.length == 1) {
							var typeMirror = variableType.typeArguments[0];

							if (typeMirror.isSubclassOf(reflectClass(Future))) {
								if (typeMirror.typeArguments.length == 1) {
									typeMirror = typeMirror.typeArguments[0];
								} else {
									throw new ArgumentError();
								}
							}

							reflect(instance).setField(symbol, Registry.lookupProvider(typeMirror.originalDeclaration.reflectedType));
						} else {
							throw new ArgumentError();
						}
					} else if (variableType is ClassMirror && variableType.reflectedType == Function) {
						throw new UnimplementedError();
					} else if (variableType is TypedefMirror && variableType.isSubtypeOf(reflectClass(ProviderFunction))) {
						if (variableType.typeArguments.length == 1) {
							var typeMirror = variableType.typeArguments[0];

							if (typeMirror.isSubclassOf(reflectClass(Future))) {
								if (typeMirror.typeArguments.length == 1) {
									typeMirror = typeMirror.typeArguments[0];
								} else {
									throw new ArgumentError();
								}
							}

							reflect(instance).setField(symbol, Registry.lookupProviderFunction(typeMirror.originalDeclaration.reflectedType));
						} else {
							throw new ArgumentError();
						}
					} else {
						throw new ArgumentError();
					}
				}
			}
		});
	}
}

_newInstanceFromClass(Type clazz) {
	ClassMirror mirror = reflectClass(clazz);
	var object = mirror.newInstance(MirrorSystem.getSymbol(""), []);
	return object.reflectee;
}
