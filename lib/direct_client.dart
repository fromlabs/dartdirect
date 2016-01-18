library dartdirect.client;

import "package:logging/logging.dart";

import 'package:dartregistry/dart_registry.dart';

import 'package:dartdirect/direct_backend.dart';

import "dart:js";
import "dart:async";
import "dart:convert";

part "src/directclient/direct_client.dart";

final Logger _libraryLogger = new Logger("dartdirect.client");
