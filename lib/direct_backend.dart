library dartdirect.backend;

import 'package:dartregistry/dart_registry.dart';

@GlobalQuantifyCapability(r"^logging.Logger$", injectable)
import "package:reflectable/reflectable.dart";

import "dart:convert";
import 'dart:async';

import 'package:logging/logging.dart';

part "src/directbackend/direct_backend.dart";
part "src/directbackend/direct_manager.dart";

final Logger _libraryLogger = new Logger("dartdirect.backend_api");
