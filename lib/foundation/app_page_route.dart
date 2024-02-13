import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';

const double _kBackGestureWidth = 20.0;
const int _kMaxDroppedSwipePageForwardAnimationTime = 800;
const int _kMaxPageBackAnimationTime = 300;
const double _kMinFlingVelocity = 1.0;

class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute(this.page, [this.enableIOSGesture = true]);

  Widget Function() page;

  final bool enableIOSGesture;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  static bool _isPopGestureEnabled<T>(PageRoute<T> route) {
    if (route.isFirst ||
        route.willHandlePopInternally ||
        route.popDisposition == RoutePopDisposition.doNotPop ||
        route.fullscreenDialog ||
        route.animation!.status != AnimationStatus.completed ||
        route.secondaryAnimation!.status != AnimationStatus.dismissed ||
        route.navigator!.userGestureInProgress ||
        App.temporaryDisablePopGesture) {
      return false;
    }

    return true;
  }

  Widget? _child;

  Widget _getChild() => _child ?? (_child = page());

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final child = _getChild();
    final Widget result = Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: child,
    );
    return result;
  }

  PageTransitionsBuilder getTransition() {
    if (App.uiMode() != UiModes.m1) {
      return FadePageTransitionBuilder();
    }
    return SlidePageTransitionBuilder();
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return getTransition().buildTransitions(
        this,
        context,
        animation,
        secondaryAnimation,
        IOSBackGestureDetector(
            gestureWidth: _kBackGestureWidth,
            enabledCallback: () => _isPopGestureEnabled<T>(this),
            onStartPopGesture: () => _startPopGesture(this),
            child: child));
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  IOSBackGestureController _startPopGesture(PageRoute<T> route) {
    return IOSBackGestureController(route.controller!, route.navigator!);
  }
}

class IOSBackGestureController {
  final AnimationController controller;

  final NavigatorState navigator;

  IOSBackGestureController(this.controller, this.navigator) {
    navigator.didStartUserGesture();
  }

  void dragEnd(double velocity) {
    const Curve animationCurve = Curves.fastLinearToSlowEaseIn;
    final bool animateForward;

    if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      final droppedPageForwardAnimationTime = min(
        lerpDouble(
                _kMaxDroppedSwipePageForwardAnimationTime, 0, controller.value)!
            .floor(),
        _kMaxPageBackAnimationTime,
      );
      controller.animateTo(1.0,
          duration: Duration(milliseconds: droppedPageForwardAnimationTime),
          curve: animationCurve);
    } else {
      navigator.pop();
      if (controller.isAnimating) {
        final droppedPageBackAnimationTime = lerpDouble(
                0, _kMaxDroppedSwipePageForwardAnimationTime, controller.value)!
            .floor();
        controller.animateBack(0.0,
            duration: Duration(milliseconds: droppedPageBackAnimationTime),
            curve: animationCurve);
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }

  void dragUpdate(double delta) {
    controller.value -= delta;
  }
}

class IOSBackGestureDetector extends StatefulWidget {
  const IOSBackGestureDetector(
      {required this.enabledCallback,
      required this.child,
      required this.gestureWidth,
      required this.onStartPopGesture,
      super.key});

  final double gestureWidth;

  final bool Function() enabledCallback;

  final IOSBackGestureController Function() onStartPopGesture;

  final Widget child;

  @override
  State<IOSBackGestureDetector> createState() => _IOSBackGestureDetectorState();
}

class _IOSBackGestureDetectorState extends State<IOSBackGestureDetector> {
  IOSBackGestureController? _backGestureController;

  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  Widget build(BuildContext context) {
    var dragAreaWidth = Directionality.of(context) == TextDirection.ltr
        ? MediaQuery.of(context).padding.left
        : MediaQuery.of(context).padding.right;
    dragAreaWidth = max(dragAreaWidth, widget.gestureWidth);
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        Positioned(
          width: dragAreaWidth,
          top: 0.0,
          bottom: 0.0,
          left: 0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) _recognizer.addPointer(event);
  }

  void _handleDragCancel() {
    assert(mounted);
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  double _convertToLogical(double value) {
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        return -value;
      case TextDirection.ltr:
        return value;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    assert(mounted);
    assert(_backGestureController != null);
    _backGestureController!.dragEnd(_convertToLogical(
        details.velocity.pixelsPerSecond.dx / context.size!.width));
    _backGestureController = null;
  }

  void _handleDragStart(DragStartDetails details) {
    assert(mounted);
    assert(_backGestureController == null);
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    assert(mounted);
    assert(_backGestureController != null);
    _backGestureController!.dragUpdate(
        _convertToLogical(details.primaryDelta! / context.size!.width));
  }
}

class FadePageTransitionBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    return FadeTransition(
      opacity: animation.drive(Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.ease))),
      child: child,
    );
  }
}

class SlidePageTransitionBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    return AnimatedBuilder(animation: animation, builder: (context, child) {
      child = SizedBox(width: screenWidth, height: screenHeight, child: child);
      child = PhysicalModel(color: Colors.transparent, elevation: 6, child: child,);
      return Stack(
        children: <Widget>[
          Positioned(
            left: screenWidth * (1 - animation.value),
            child: child,
          ),
        ],
      );
    }, child: child);
  }
}
