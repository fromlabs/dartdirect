part of directbackendapi;

String DIRECT_ENVIROMENT;

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
