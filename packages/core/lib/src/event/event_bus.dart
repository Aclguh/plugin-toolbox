import 'dart:async';
import 'app_event.dart';

abstract class EventBus {
  void fire(AppEvent event);
  Stream<T> on<T extends AppEvent>();
  void dispose();
}

class EventBusImpl implements EventBus {
  final StreamController<AppEvent> _controller = StreamController<AppEvent>.broadcast();

  @override
  void fire(AppEvent event) => _controller.add(event);

  @override
  Stream<T> on<T extends AppEvent>() =>
      _controller.stream.where((e) => e is T).cast<T>();

  @override
  void dispose() => _controller.close();
}
