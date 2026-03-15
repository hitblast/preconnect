import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'package:preconnect/tools/push_notifications_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await PushNotificationsService().initialize();
  final bootstrapState = await MyApp.bootstrap();
  runApp(MyApp(bootstrapState: bootstrapState));
}
