library directbackendapi;

import 'package:dartregistry/dart_registry.dart';

@GlobalQuantifyCapability(r"^logging.Logger$", Injectable)
import "package:reflectable/reflectable.dart";

import "dart:convert";
import 'dart:async';

import 'package:logging/logging.dart';

part "src/directbackend/direct_backend_api.dart";
part "src/directbackend/direct_manager.dart";
