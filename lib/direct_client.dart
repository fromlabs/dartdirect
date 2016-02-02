library dartdirect.client;

import "dart:js";
import "dart:async";
import "dart:convert";

import "package:stack_trace/stack_trace.dart";

import "package:logging/logging.dart";
import 'package:dartregistry/dart_registry.dart';
import 'package:dartdirect/direct_backend.dart';

part "src/directclient/direct_client.dart";

final Logger _libraryLogger = new Logger("dartdirect.client");
