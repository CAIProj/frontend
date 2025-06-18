import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tracking_app/constants/app_constants.dart';
import 'package:tracking_app/services/framework_controller.dart';
import 'package:tracking_app/services/notification_controller.dart' as n;

class AccountPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();

  late final FrameworkController _frameworkClientController =
      Provider.of<FrameworkController>(context, listen: false);

  late final n.NotificationController _notificationController =
      Provider.of<n.NotificationController>(context, listen: false);
  bool _loading = false;

  // Login or register
  bool _isLogin = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  List<Widget> _loginElements(BuildContext context) {
    return [
      SizedBox(
        width: 200,
        child: TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: 'Username',
            hintStyle: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          style: TextStyle(
            fontSize: AppConstants.textSizeM,
            color: AppConstants.primaryTextColor,
          ),
        ),
      ),
      SizedBox(
        width: 200,
        child: TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor),
        ),
      ),
      SizedBox(height: 12),
      TextButton(
        style: AppConstants.primaryButtonStyle,
        onPressed: () async {
          setState(() {
            _loading = true;
          });
          final success = await _frameworkClientController.login(
            _usernameController.text,
            _passwordController.text,
          );
          if (success) {
            _notificationController.addNotification(
              n.Notification(
                type: n.NotificationType.General,
                text: 'Logged in',
              ),
            );
          } else {
            _notificationController.addNotification(
              n.Notification(
                type: n.NotificationType.Error,
                text: 'Incorrect username or password',
              ),
            );
          }
          setState(() {
            _loading = false;
          });
        },
        child: Text(
          'Login',
          style: TextStyle(
            fontSize: AppConstants.textSizeM,
            color: AppConstants.primaryTextColor,
          ),
        ),
      ),
    ];
  }

  List<Widget> _registerElements(BuildContext context) {
    return [
      SizedBox(
        width: 200,
        child: TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: 'Username',
            hintStyle: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          style: TextStyle(
            fontSize: AppConstants.textSizeM,
            color: AppConstants.primaryTextColor,
          ),
        ),
      ),
      SizedBox(
        width: 200,
        child: TextFormField(
          controller: _emailController,
          decoration: InputDecoration(
            hintText: 'Email',
            hintStyle: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          style: TextStyle(
            fontSize: AppConstants.textSizeM,
            color: AppConstants.primaryTextColor,
          ),
        ),
      ),
      SizedBox(
        width: 200,
        child: TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor),
        ),
      ),
      SizedBox(
        width: 200,
        child: TextFormField(
          controller: _passwordConfirmController,
          decoration: InputDecoration(
            hintText: 'Confirm Password',
            hintStyle: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor),
        ),
      ),
      SizedBox(height: 12),
      TextButton(
        style: AppConstants.primaryButtonStyle,
        onPressed: () async {
          if (_passwordController.text != _passwordConfirmController.text) {
            _notificationController.addNotification(
              n.Notification(
                type: n.NotificationType.Error,
                text: 'Passwords do not match',
              ),
            );
            return;
          }
          setState(() {
            _loading = true;
          });
          final (success, errMsg) = await _frameworkClientController.register(
            _usernameController.text,
            _emailController.text,
            _passwordController.text,
          );
          if (success) {
            _notificationController.addNotification(
              n.Notification(
                type: n.NotificationType.General,
                text: 'Account created, please log in',
              ),
            );
            setState(() {
              _isLogin = true;
            });
          } else {
            _notificationController.addNotification(
              n.Notification(
                type: n.NotificationType.Error,
                text: 'Error occurred: $errMsg',
              ),
            );
          }
          setState(() {
            _loading = false;
          });
        },
        child: Text(
          'Login',
          style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor),
        ),
      ),
    ];
  }

  Widget formWidget(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = true;
                    });
                  },
                  child: Text(
                    "Login",
                    style: TextStyle(
                        fontSize: AppConstants.textSizeL,
                        color: AppConstants.primaryTextColor,
                        fontWeight:
                            _isLogin ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
                SizedBox(width: 20),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = false;
                    });
                  },
                  child: Text(
                    "Register",
                    style: TextStyle(
                        fontSize: AppConstants.textSizeL,
                        color: AppConstants.primaryTextColor,
                        fontWeight:
                            !_isLogin ? FontWeight.bold : FontWeight.normal),
                  ),
                )
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _isLogin
                  ? _loginElements(context)
                  : _registerElements(context),
            ),
          ),
          Spacer(flex: 1)
        ],
      ),
    );
  }

  Widget loggedInWidget(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                'Logged in',
                style: TextStyle(
                  fontSize: AppConstants.textSizeL,
                  color: AppConstants.primaryTextColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                if (kDebugMode)
                  TextButton(
                    style: AppConstants.primaryButtonStyle,
                    onPressed: () async {
                      final files = await _frameworkClientController
                          .getUploadedGPXFiles();

                      if (files != null) {
                        _notificationController.addNotification(n.Notification(
                            type: n.NotificationType.General,
                            text: 'Files on server: ${files.length}'));
                      }
                    },
                    child: Text(
                      '[Debug] See file count on server',
                      style: TextStyle(
                        fontSize: AppConstants.textSizeM,
                        color: AppConstants.primaryTextColor,
                      ),
                    ),
                  ),
                if (kDebugMode)
                  TextButton(
                    style: AppConstants.primaryButtonStyle,
                    onPressed: () async {
                      final files = await _frameworkClientController
                          .getUploadedGPXFiles();
                      if (files != null) {
                        files.forEach((v) async {
                          bool res = await _frameworkClientController
                              .deleteGPXFile(v.id);
                          if (res) {
                            _notificationController.addNotification(
                                n.Notification(
                                    type: n.NotificationType.General,
                                    text: 'Deleted file ${v.id}'));
                          }
                        });
                      }
                    },
                    child: Text(
                      '[Debug] Delete all GPX files on server',
                      style: TextStyle(
                        fontSize: AppConstants.textSizeM,
                        color: AppConstants.primaryTextColor,
                      ),
                    ),
                  ),
                TextButton(
                  style: AppConstants.primaryButtonStyle,
                  onPressed: () {
                    _frameworkClientController.logout();
                    _notificationController.addNotification(n.Notification(
                        type: n.NotificationType.General, text: 'Logged out'));
                  },
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: AppConstants.textSizeM,
                      color: AppConstants.primaryTextColor,
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // For rebuilding purposes
    final FrameworkController _frameworkClientController =
        Provider.of<FrameworkController>(context, listen: true);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        foregroundColor: AppConstants.primaryTextColor,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppConstants.appBarGradient),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppConstants.appBodyGradient),
        child: SafeArea(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                    color: AppConstants.primaryTextColor,
                  ))
                : _frameworkClientController.isLoggedIn
                    ? loggedInWidget(context)
                    : formWidget(context)),
      ),
    );
  }
}
