part of directserver;

class MultipartConverter extends Converter<List<int>, MultipartRequest> {

  Map<String, List<String>> headers;
  MultipartConverter(this.headers);

  ChunkedConversionSink startChunkedConversion(Sink sink) {
    return new MultipartSink(headers, sink);
  }

  @override
  MultipartRequest convert(List<int> input) {
    throw new UnsupportedError("Convert unsupported");
  }
}

class MultipartSink extends ChunkedConversionSink<List<int>> {

  static const num BOUNDARY = 1;
  static const num CONTENT = 2;

  static final List<int> ENCODED_CONTENT_MARK = UTF8.encode("\r\n\r\n");
  static const String END_MARK = "--";

  Map<String, List<String>> headers;
  MultipartRequestImpl _response;
  // Map<String, List<RequestParameter>> _requestParameters;

  List<int> encodedBoundary;

  Sink<MultipartRequest> sink;

  num nextStatus;
  List<int> nextEncodedMarker;

  List<int> lastChunk;
  num lastChunkIndex;
  List<int> leftEncodedMarker;

  Queue<List<int>> headerChunkQueue;

  RequestParameterImpl _currentRequestParameter;

  MultipartSink(this.headers, this.sink) {
    this.headerChunkQueue = new Queue();

    String contentType = headers["content-type"][0];
    Map<String, String> contentTypes = {};
    contentType.split("; ").forEach((key) {
      var data = key.split("=");
      contentTypes[data[0]] = data.length > 1 ? data[1] : null;
    });

    this.encodedBoundary = UTF8.encode(END_MARK + contentTypes["boundary"]);

    _response = new MultipartRequestImpl(headers);
    this.sink.add(_response);

    lookForBoundaryMarker();
  }

  void lookForBoundaryMarker() {
    // print("lookForBoundaryMarker: $nextStatus");

    if (nextStatus != null && nextStatus != CONTENT) {
      throw new StateError("Status error");
    }

    if (nextStatus == CONTENT) {
      matchHeader(popHeader());
    }

    nextStatus = BOUNDARY;
    nextEncodedMarker = encodedBoundary;
    leftEncodedMarker = nextEncodedMarker;

    process();
  }

  void matchHeader(String header) {
    matchContent();

    _currentRequestParameter = new RequestParameterImpl(header);
    _response.addParameter(_currentRequestParameter);
  }

  String popHeader() {
    var list =
        new List.from(headerChunkQueue.expand((chunk) => chunk), growable: false);
    headerChunkQueue.clear();
    return UTF8.decode(list).trim();
  }

  void lookForContentMarker() {
    // print("lookForContentMarker: $nextStatus");

    if (nextStatus != BOUNDARY) {
      throw new StateError("Status error");
    }

    nextStatus = CONTENT;
    nextEncodedMarker = ENCODED_CONTENT_MARK;
    leftEncodedMarker = nextEncodedMarker;

    process();
  }

  @override
  void add(List<int> chunk) {
    // print("*************** add: ${chunk.length}");

    _response.updateProgress(chunk.length);

    this.lastChunk = chunk;
    this.lastChunkIndex = 0;

    this.process();
  }

  @override
  void close() {
    pushChunk(leftEncodedMarker, 0, leftEncodedMarker.length);

    if (this.nextStatus == CONTENT) {

      // controllo che il content buffer sia uguale alla stringa di chiusura
      var header = popHeader();

      if (header == END_MARK) {
        matchContent();

        this.sink.close();

        _response.close();
      } else {
        throw new StateError("Close mark error");
      }
    } else {
      throw new StateError("Close state error");
    }
  }

  void matchContent() {
    if (_currentRequestParameter != null) {
      _currentRequestParameter.commit();

      _currentRequestParameter = null;
    }
  }

  void process() {
    if (this.lastChunk != null && this.lastChunk.isNotEmpty) {
      var index =
          indexTo(this.lastChunk, this.leftEncodedMarker, this.lastChunkIndex);
      if (index != -1) {
        // trovato matching
        if (this.nextEncodedMarker.length == this.leftEncodedMarker.length) {
          // matching intero
          var newIndex = index + this.leftEncodedMarker.length;
          if (newIndex > this.lastChunk.length) {
            // matching overflow genera ricerca parziale
            // print("matching overflow genera ricerca parziale");
            pushChunk(this.lastChunk, this.lastChunkIndex, index);

            this.leftEncodedMarker =
                this.nextEncodedMarker.sublist(this.lastChunk.length - index);
            this.lastChunk = [];
            this.lastChunkIndex = 0;
          } else {
            // matching intero completato
            // print("matching intero completato");
            pushChunk(this.lastChunk, this.lastChunkIndex, index);

            this.lastChunkIndex = newIndex;

            match();
          }
        } else {
          if (index == 0) {
            // matching parziale
            var newIndex = index + this.leftEncodedMarker.length;
            if (newIndex > this.lastChunk.length) {
              // matching overflow genera altra ricerca parziale
              // print("matching overflow genera altra ricerca parziale");

              this.leftEncodedMarker =
                  this.leftEncodedMarker.sublist(this.lastChunk.length - index);
              this.lastChunk = [];
              this.lastChunkIndex = 0;
            } else {
              // matching parziale completato
              // print("matching parziale completato");
              this.lastChunkIndex = newIndex;

              match();
            }
          } else {

                // matching parziale annullato genera ricerca matching intero dall'inizio

                // print("matching parziale annullato genera ricerca matching intero dall'inizio");
            pushChunk(
                this.nextEncodedMarker,
                0,
                this.nextEncodedMarker.length - this.leftEncodedMarker.length);

            this.leftEncodedMarker = this.nextEncodedMarker;
            this.lastChunkIndex = 0;
          }
        }
      } else {
        if (this.nextEncodedMarker.length == this.leftEncodedMarker.length) {
          // non trovato matching
          // print("non trovato matching");
          pushChunk(this.lastChunk, this.lastChunkIndex, this.lastChunk.length);
          this.lastChunk = [];
          this.lastChunkIndex = 0;
        } else {

              // non trovato matching parziale genera ricerca matching intero dall'inizio

              // print("non trovato matching parziale genera ricerca matching intero dall'inizio");
          pushChunk(
              this.nextEncodedMarker,
              0,
              this.nextEncodedMarker.length - this.leftEncodedMarker.length);
          this.leftEncodedMarker = this.nextEncodedMarker;
        }
      }

      process();
    }
  }

  void match() {
    switch (nextStatus) {
      case BOUNDARY:
        lookForContentMarker();
        break;
      case CONTENT:
        lookForBoundaryMarker();
        break;
      default:
        throw new StateError("Unkown next status $nextStatus");
    }
  }

  void pushChunk(List<int> data, num startIndex, num endIndex) {
    // print("$nextStatus: push intervallo da $startIndex-$endIndex");
    if (endIndex > startIndex) {

          // print("$nextStatus: push intervallo da $startIndex-$endIndex di $data");

      var chunk = data.sublist(startIndex, endIndex);

      switch (nextStatus) {
        case BOUNDARY:
          pushContentChunk(chunk);

          break;
        case CONTENT:
          pushHeaderChunk(chunk);

          break;
        default:
          throw new StateError("Unkown next status $nextStatus");
      }
    }
  }

  void pushContentChunk(List<int> data) {
    // print("Push content: $header");
    _currentRequestParameter.addChunk(data);
  }

  void pushHeaderChunk(List<int> data) {
    // print("Push header: $header");
    headerChunkQueue.add(data);
  }

  num indexTo(List<int> data, List<int> pattern, num index) {
    for (num i1 = index; i1 < data.length; i1++) {
      bool found = true;
      for (num i2 = 0; i2 < pattern.length; i2++) {
        if (i1 + i2 == data.length) {
          break;
        } else if (data[i1 + i2] != pattern[i2]) {
          found = false;
          break;
        }
      }
      if (found) {
        return i1;
      }
    }
    return -1;
  }
}

class MultipartRequestImpl implements MultipartRequest {

  Map<String, List<String>> _headers;
  Map<String, List<RequestParameter>> _parameters;
  StreamController<RequestProgress> _progressController =
      new StreamController(sync: true);
  StreamController<RequestParameter> _parameterController =
      new StreamController(sync: true);

  num contentLength;

  RequestProgressImpl _progress;

  Completer _completer;

  List<Future> _allFutures;
  FutureQueue _progressQueue;

  MultipartRequestImpl(this._headers) {
    this._completer = new Completer();
    this._allFutures = [];
    this._parameters = {};

    var contentLengthString = getFirstHeader("content-length");
    if (contentLengthString != null) {
      contentLength = int.parse(contentLengthString);
    }

    _progress = new RequestProgressImpl(contentLength);
    _progressController.add(progress);

    this._progressQueue = new FutureQueue();
    this._allFutures.add(_progressQueue.future);
    this._progressController.stream.listen((RequestProgress progress) {
      _progressQueue.add(progress);
    }, onDone: () {
      _progressQueue.close();
    });
  }

  String getFirstHeader(String name) {
    var values = this._headers[name];
    return values != null ? values.first : null;
  }

  void updateProgress(num chunkLength) {
    _progress = _progress.update(chunkLength);
    _progressController.add(progress);
  }

  void addParameter(RequestParameter parameter) {
    var values = _parameters[parameter.name];
    if (values == null) {
      values = [];
      _parameters[parameter.name] = values;
    }
    values.add(parameter);
    _parameterController.add(parameter);
  }

  RequestProgress get progress => _progress;

  void close() {
    _progressController.close().whenComplete(
        () => _parameterController.close()).whenComplete(() {
      Future.forEach(_allFutures, (future) => future).then((_) {
        _completer.complete();
      }).catchError((error, stacktrace) {
        _completer.completeError(error, stacktrace);
      });
    });
  }

  Map<String, List<RequestParameter>> get parameters => _parameters;

  @override
  Future get future => _completer.future;

  @override
  void onProgress(progressHandler(RequestProgress progress, bool closed)) {
    _progressQueue.bind(progressHandler);
  }

  @override
  void onUploadParameter(parameterHandler(RequestParameter parameter)) {
    _parameterController.stream.listen((RequestParameterImpl parameter) {
      _allFutures.add(parameter.onCommit);
      if (parameter.isUpload) {
        parameterHandler(parameter);
      } else {
        parameter.onChunk((data, closed) => null);
      }
    });
  }
}

class RequestProgressImpl implements RequestProgress {
  final num value;
  final num total;
  final bool isClose;

  RequestProgressImpl(this.total)
      : this.value = 0,
        this.isClose = false;

  RequestProgressImpl._update(num delta, RequestProgressImpl old)
      : this.value = old.value + delta,
        this.total = old.total,
        this.isClose = false;

  RequestProgressImpl._close(RequestProgressImpl old)
      : this.total = old.total,
        this.value = old.value,
        this.isClose = true;

  RequestProgress update(num value) =>
      new RequestProgressImpl._update(value, this);

  RequestProgress close() => new RequestProgressImpl._close(this);

  String toString() => "$value/$total";
}

class RequestParameterImpl implements RequestParameter {

  static final _LINE_SPLITTER = new LineSplitter();

  String _name;
  String _value;

  Map<String, Map<String, String>> _headers;

  StringBuffer _valueBuffer;

  FutureQueue _chunkQueue;

  StreamController<List<int>> _chunkController =
      new StreamController(sync: true);

  RequestParameterImpl(String header) {
    _headers = {};
    _LINE_SPLITTER.convert(header).forEach((line) {
      var i = line.indexOf(":");
      var name = line.substring(0, i);
      var values = {};
      var left = line.substring(i + 1);
      left.split(";").forEach((part) {
        part = part.trim();
        var i2 = part.trim().indexOf("=");
        if (i2 != -1) {
          values[part.substring(0, i2)] =
              part.substring(i2 + 2, part.length - 1);
        } else {
          values[part] = "";
        }
      });
      _headers[name] = values;
    });
    _name = _headers["Content-Disposition"]["name"];
    _valueBuffer = new StringBuffer();
    _chunkQueue = new FutureQueue();
  }

  bool get isUpload => _headers.containsKey("Content-Type");

  String get name => _name;

  String get value {
    if (!_chunkController.isClosed) {
      throw new StateError("Parameter value is not ready");
    }
    return _value;
  }

  void addChunk(List<int> data) {
    if (isUpload) {
      _chunkController.add(data);
    } else {
      _valueBuffer.write(UTF8.decode(data));
    }
  }

  void commit() {
    // print("Close chunk controller: $name");
    _value = _valueBuffer.toString();
    _valueBuffer = null;

    if (_value.endsWith("\r\n")) {
      _value = _value.substring(0, _value.length - 2);
    }

    _chunkController.close();
  }

  Future get onCommit => _chunkQueue.future;

  @override
  void onChunk(chunkHandler(List<int> chunk, bool closed)) {
    _chunkQueue.bind(chunkHandler);
    _chunkController.stream.listen((List<int> data) {
      _chunkQueue.add(data);
    }, onDone: () {
      _chunkQueue.close();
    });
  }
}

class FutureQueue<T> {

  var _computation;

  T _value;

  bool _closed;

  Completer _completer;

  Future _future;

  FutureQueue() {
    this._completer = new Completer();
    this._computation = (value, closed) {};
    this._future = new Future.value();
    this._closed = false;
  }

  void bind(computation(T, bool closed)) {
    this._computation = computation;
  }

  Future add(T value) {
    _value = value;
    _future = _future.then((_) => _computation(value, false));
    return _future;
  }

  Future close() {
    _closed = true;
    _future.then((_) => _computation([], true)).then((_) {
      _completer.complete();
    }).catchError((error, stacktrace) {
      print("Errore sulla close");
      _completer.completeError(error, stacktrace);
    });
    return future;
  }

  Future get future => _completer.future;
}
