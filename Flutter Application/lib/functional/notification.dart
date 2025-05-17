import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tracking_app/constants/app_constants.dart';

enum NotificationType { General, Success, Error }

class Notification {
  final NotificationType type;
  final String text;
  final int timeInserted;

  Notification({required this.type, required this.text})
      : timeInserted = DateTime.now().millisecondsSinceEpoch;
}

class NotificationController with ChangeNotifier {
  OverlayEntry? _entry;
  List<Notification> notifications = [];

  void addNotification(Notification notification) async {
    notifications.add(notification);
    notifyListeners();
  }

  void initOverlay(BuildContext context) {
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => NotificationContainer());
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Overlay.of(context).insert(_entry!));
    }
  }
}

class NotificationContainer extends StatefulWidget {
  const NotificationContainer();

  @override
  State<NotificationContainer> createState() => _NotificationContainerState();
}

class _NotificationContainerState extends State<NotificationContainer> {
  _NotificationContainerState();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final NotificationController _notificationController =
        context.watch<NotificationController>();

    List<Widget> elements = [];
    _notificationController.notifications.forEach((e) {
      elements.add(SizedBox(height: 12));
      elements.add(NotificationInstance(
        key: Key(e.timeInserted.toString()),
        notificationMessageType: e.type,
        text: e.text,
        onFinish: () {
          if (mounted) {
            setState(() {
              _notificationController.notifications.remove(e);
            });
          }
        },
      ));
    });
    return SafeArea(child: Column(children: elements));
  }
}

class NotificationInstance extends StatefulWidget {
  final NotificationType notificationMessageType;
  final String text;
  final VoidCallback? onFinish;

  const NotificationInstance(
      {required Key key,
      required this.notificationMessageType,
      required this.text,
      this.onFinish})
      : super(key: key);

  @override
  State<NotificationInstance> createState() => _NotificationInstanceState();
}

class _NotificationInstanceState extends State<NotificationInstance>
    with TickerProviderStateMixin {
  final Duration _transitionTime = const Duration(milliseconds: 400);
  double _opacity = 0.0;

  late final AnimationController _controller = AnimationController(
    duration: _transitionTime,
    vsync: this,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();

    // Transitioning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initial transition
      if (mounted) {
        setState(() {
          _opacity = 1.0;
        });
        _controller.forward();
      }

      // Fade out after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _opacity = 0.0;
          });
          _controller.reverse();

          Future.delayed(_transitionTime, () {
            if (mounted && widget.onFinish != null) {
              widget.onFinish!();
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getColor() {
    switch (widget.notificationMessageType) {
      case NotificationType.General:
        return AppConstants.general;
      case NotificationType.Success:
        return AppConstants.success;
      case NotificationType.Error:
        return AppConstants.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: _transitionTime,
      child: SizeTransition(
        axis: Axis.vertical,
        sizeFactor: _animation,
        child: Center(
          child: Dismissible(
            key: widget.key!,
            direction: DismissDirection.horizontal,
            onDismissed: (direction) {
              if (widget.onFinish != null) {
                widget.onFinish!();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getColor(),
                borderRadius: BorderRadius.circular(20),
              ),
              constraints: BoxConstraints(minWidth: 100),
              child: IntrinsicWidth(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppConstants.textSizeM,
                        color: Colors.white,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
