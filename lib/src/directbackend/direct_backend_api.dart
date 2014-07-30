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

	Map<String, dynamic> _params;
	var _id;
	int _start;
	int _limit;
	int _page;

	DirectSort _sort;
	List<DirectFilter> _filters;

	DirectParams(Map<String, dynamic> params) {
		this._params = params;
		this._id = params["id"];
		this._start = params["start"] != null ? params["start"] : 0;
		this._limit = params["limit"] != null ? params["limit"] : 0;
		this._page = params["page"] != null ? params["page"] : 0;

		// sort
		this._sort = _parseSorts(params);

		// filters
		this._filters = _parseFilters(params);
	}

	get id => _id;

	int get start => _start;

	int get limit => _limit;

	int get page => _page;

	DirectSort get sort => _sort;

	List<DirectFilter> get filters => _filters;

	Map<String, dynamic> get params => _params;

	Set<DirectFilter> getFiltersByName(String name) {
		var result = new Set();
		filters.forEach((DirectFilter directFilter) {
			if (directFilter.field == name) {
				result.add(directFilter);
			}
		});
		return result;
	}

	bool hasFilterOn(String name) {
		bool hasFilter = false;
		filters.forEach((DirectFilter directFilter) {
			if (directFilter.field == name) {
				hasFilter = true;
				return;
			}
		});
		return hasFilter;
	}

	DirectSort _parseSorts(Map<String, dynamic> params) {
		String sortProperty = null;
		String sortDirection = null;
		if (params.containsKey("sort")) {
			List<Map<String, dynamic>> sorts = params["sort"];
			if (!sorts.isEmpty) {
				sortProperty = sorts[0]["property"];
				sortDirection = sorts[0]["direction"];
			}
		}
		return new DirectSort(sortProperty, sortDirection);
	}

	List<DirectFilter> _parseFilters(Map<String, dynamic> params) {
		List<Map<String, dynamic>> filterMaps = _getFilterMaps(params);

		List<DirectFilter> filters = new List<DirectFilter>();
		if (filterMaps != null) {
			filterMaps.forEach((directFilterMap) {
				filters.add(new DirectFilter(directFilterMap));
			});
		}

		return filters;
	}

	List<Map<String, dynamic>> _getFilterMaps(Map<String, dynamic> params) {
		return params["filter"];
	}
}

class DirectSort {
	String _property;
	String _direction;

	DirectSort(String property, String direction) {
		this._property = property != null && property.isNotEmpty ? property : null;
		this._direction = direction != null && direction.isNotEmpty ? direction : null;
	}

	String get property => _property;

	String get direction => _direction;

	String getPropertyOrDefault(String defaultProperty) {
		return property != null && property.isNotEmpty ? defaultProperty : null;
	}

	String getDirectionOrDefault(String defaultDirection) {
		return direction != null && direction.isNotEmpty ? defaultDirection : null;
	}
}

class DirectFilter {

	static const String NUMERIC_TYPE = "NUMERIC";
	static const String STRING_TYPE = "STRING";
	static const String DATE_TYPE = "DATE";
	static const String LIST_TYPE = "LIST";
	static const String BOOLEAN_TYPE = "BOOLEAN";
	static const String COMBO_TYPE = "COMBO";

	static const String EQUAL_COMPARATOR = "EQUAL";
	static const String GREATER_THAN_COMPARATOR = "GREATER_THAN";
	static const String LESS_THAN_COMPARATOR = "LESS_THAN";
	static const String LIKE_COMPARATOR = "LIKE";

	String _field;
	dynamic _dataValue;
	String _dataType;
	String _dataComparator;

	DirectFilter(Map<String, Object> filterMap) {
		this._field = filterMap["property"];
		var dataType = null;
		if (filterMap.containsKey("type")) {
			switch (filterMap["type"]) {
				case "int":
					dataType = NUMERIC_TYPE;
					break;
				case "numeric":
					dataType = NUMERIC_TYPE;
					break;
				case "string":
					dataType = STRING_TYPE;
					break;
				case "date":
					dataType = DATE_TYPE;
					break;
				case "boolean":
					dataType = BOOLEAN_TYPE;
					break;
				case "list":
					dataType = LIST_TYPE;
					break;
				case "combo":
					dataType = COMBO_TYPE;
					break;
			}
		}
		this._dataType = dataType;

		switch (dataType) {
			case NUMERIC_TYPE:
				this._dataValue = _getDoubleDataValue(filterMap["value"]);
				break;
			case BOOLEAN_TYPE:
				this._dataValue = _getBooleanDataValue(filterMap["value"]);
				break;
			default:
				this._dataValue = filterMap["value"];
				break;
		}

		var dataComparator = null;
		if (filterMap.containsKey("operator")) {
			switch (filterMap["operator"]) {
				case "eq":
					dataComparator = EQUAL_COMPARATOR;
					break;
				case "lt":
					dataComparator = LESS_THAN_COMPARATOR;
					break;
				case "gt":
					dataComparator = GREATER_THAN_COMPARATOR;
					break;
				case "like":
					dataComparator = LIKE_COMPARATOR;
					break;
			}
		}
		this._dataComparator = dataComparator;
	}

	bool _getBooleanDataValue(value) {
		if (value == null) {
			return null;
		} else if (value is bool) {
			return value;
		} else {
			return value == "true";
		}
	}

	num _getDoubleDataValue(value) {
		if (value == null) {
			return null;
		} else if (value is num) {
			return value;
		} else {
			return num.parse(value);
		}
	}

	String get field => _field;

	String get dataType => _dataType;

	String get dataComparator => _dataComparator;

	get dataValue => _dataValue;

	String get stringValue => _dataValue;

/*
  num get doubleValue => _dataValue;

  bool get booleanValue => dataValue;

  public List getListDataValue() {
    return (List) dataValue;
  }

  public Date getDateDataValue() throws ParseException {
    return new SimpleDateFormat("yyyy-MM-dd").parse((String) dataValue);
  }
*/
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
	Future onRequest(Future directCall(String base, String application, String path, String json, Map<String,
			List<String>> headers, MultipartRequest multipartRequest, DirectCallback callback));
}
