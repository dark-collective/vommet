import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class StarTrailsBackground extends StatefulWidget {
  const StarTrailsBackground({super.key, this.child});
  final Widget? child;

  @override
  State<StarTrailsBackground> createState() => _StarTrailsBackgroundState();
}

class _StarTrailsBackgroundState extends State<StarTrailsBackground> {
  static bool loadingShader = false;
  static FragmentShader? shader;
  late Timer timer;
  double delta = 0;
  bool animate = true;

  void loadShader() async {
    loadingShader = true;

    var program =
        await FragmentProgram.fromAsset('assets/shader/constellation.frag');
    shader = program.fragmentShader();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (mounted) {
        setState(() {
          loadingShader = false;
        });
      }
    });
  }

  // Vommet: no runtime shader in the WebAssembly build. Skwasm (Flutter
  // 3.47) sometimes fails to compile constellation.frag ("unknown identifier
  // 't'") and then traps with "null function", killing the login page. The
  // JS/CanvasKit build and native builds compile it fine.
  static const bool useShader = !kIsWasm;

  @override
  void initState() {
    super.initState();
    if (!useShader) {
      animate = false;
      return;
    }
    if (shader == null && loadingShader == false) {
      loadShader();
    }

    WidgetsBinding.instance.addPostFrameCallback(update);

    timer = Timer.periodic(const Duration(milliseconds: 16), frameTimer);
  }

  void frameTimer(Timer timer) {
    if (animate) {
      setState(() {
        delta += 1 / 60;
      });
    } else {
      timer.cancel();
    }
  }

  @override
  void dispose() {
    if (useShader) timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!useShader) {
      // The shader's background colour, without the stars.
      return Container(
        color: const Color.fromARGB(255, 10, 10, 26),
        child: widget.child,
      );
    }
    if (shader == null) {
      return const Center(child: CircularProgressIndicator());
    } else {
      return CustomPaint(
        painter: StarTrailsPainter(shader!, delta * .3),
        child: Container(
          child: widget.child,
        ),
      );
    }
  }

  Duration? previous;
  int slowFrames = 0;
  void update(Duration timeStamp) {
    if (previous != null) {
      var diff = timeStamp - previous!;
      var fps = 1000 / diff.inMilliseconds;

      if (fps < 30) {
        slowFrames += 1;
      }

      if (slowFrames > 10) {
        print("Disabling splash animation due to poor performance");
        animate = false;
      }
    }

    if (animate) {
      previous = timeStamp;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(update);
      }
    }
  }
}

class StarTrailsPainter extends CustomPainter {
  final FragmentShader shader;
  final double time;

  const StarTrailsPainter(this.shader, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, (time * 0.3) + 10);

    paint.shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
