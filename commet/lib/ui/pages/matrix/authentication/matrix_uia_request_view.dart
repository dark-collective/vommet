import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
// have to do it this way to avoid some widgetbook codegen issue
// ignore: implementation_imports
import 'package:matrix/src/utils/uia_request.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart' as material;

class MatrixUIARequestView extends StatefulWidget {
  const MatrixUIARequestView(this.state,
      {this.onSubmitAuthentication,
      required this.nextSteps,
      super.key,
      this.onFail,
      this.onSubmitSso,
      this.onRetry,
      this.onOpenResetApproval,
      this.onSuccess});
  final UiaRequestState state;
  final Set<String> nextSteps;
  final Function(String password)? onSubmitAuthentication;
  final Function()? onSubmitSso;

  /// Vommet: retry the request after a browser step.
  final Function()? onRetry;

  /// Vommet: open the account page to approve a cross-signing reset.
  final Function()? onOpenResetApproval;
  final Function()? onSuccess;
  final Function()? onFail;

  @override
  State<MatrixUIARequestView> createState() => _MatrixUIARequestViewState();
}

enum UIAStep {
  password,
  sso,
  crossSigningReset,
}

class _MatrixUIARequestViewState extends State<MatrixUIARequestView> {
  TextEditingController passwordFieldController = TextEditingController();
  bool get canUsePassword => widget.nextSteps.contains("m.login.password");
  bool get canUseSso => widget.nextSteps.contains("m.login.sso");
  bool get canApproveReset =>
      widget.nextSteps.contains("org.matrix.cross_signing_reset");

  bool get canUseAnyNextStep => canUsePassword || canUseSso || canApproveReset;

  UIAStep? pickedStep;

  @override
  void initState() {
    if (canUsePassword && !canUseSso) {
      pickedStep = UIAStep.password;
    } else if (canApproveReset && !canUsePassword && !canUseSso) {
      pickedStep = UIAStep.crossSigningReset;
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: buildView(),
      ),
    );
  }

  Widget buildView() {
    switch (widget.state) {
      case UiaRequestState.done:
        return done(context);
      case UiaRequestState.fail:
        return fail(context);
      case UiaRequestState.loading:
        return loading();
      case UiaRequestState.waitForUser:
        return pickedStep == null ? showAvailableSteps() : showPickedStep();
    }
  }

  Widget showAvailableSteps() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (canUsePassword)
            tiamat.Button(
              text: "Continue with password",
              onTap: () => setState(() {
                pickedStep = UIAStep.password;
              }),
            ),
          if (canApproveReset)
            tiamat.Button(
                text: "Approve on my account page",
                onTap: () {
                  widget.onOpenResetApproval?.call();
                  setState(() {
                    pickedStep = UIAStep.crossSigningReset;
                  });
                }),
          if (canUseSso)
            tiamat.Button(
                text: "Continue with SSO",
                onTap: () {
                  widget.onSubmitSso?.call();
                  setState(() {
                    pickedStep = UIAStep.sso;
                  });
                }),
          if (canUseAnyNextStep == false) ...[
            tiamat.Text.labelLow(
                "Sorry, none of the authentication methods provided by the server are supported."),
            tiamat.Text.labelLow(widget.nextSteps.toString()),
          ]
        ],
      ),
    );
  }

  Widget showPickedStep() {
    if (pickedStep == UIAStep.password) {
      return userPasswordInput();
    }

    switch (pickedStep!) {
      case UIAStep.password:
        return userPasswordInput();
      case UIAStep.sso:
        return browserStep(
            "Finish signing in in your browser, then come back here.");
      case UIAStep.crossSigningReset:
        return browserStep(
            "Your server asks you to approve this on your account page. Open "
            "it, approve, then come back here.",
            open: widget.onOpenResetApproval);
    }
  }

  /// Vommet: a step done in the browser, with a way to carry on (upstream
  /// showed a spinner forever).
  Widget browserStep(String text, {Function()? open}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        tiamat.Text.label(text),
        if (open != null)
          tiamat.Button(text: "Open account page", onTap: () => open()),
        tiamat.Button(
            text: "I've finished in the browser",
            onTap: () => widget.onRetry?.call()),
      ],
    );
  }

  Widget userPasswordInput() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        TextInput(
          placeholder: "Account Password",
          obscureText: true,
          controller: passwordFieldController,
        ),
        SizedBox(
            height: 40,
            child: Button(
              text: CommonStrings.promptSubmit,
              onTap: () => widget.onSubmitAuthentication
                  ?.call(passwordFieldController.text),
            ))
      ],
    );
  }

  Widget loading() {
    return const Center(
      child: material.CircularProgressIndicator(),
    );
  }

  Widget done(BuildContext context) {
    Navigator.pop(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                material.Icons.verified_user_rounded,
                color: material.Colors.green.shade400,
                size: 40,
              ),
            ),
            const tiamat.Text.largeTitle("Success!")
          ],
        ),
        SizedBox(
          height: 40,
          width: 200,
          child: tiamat.Button.success(
            text: CommonStrings.promptContinue,
            onTap: () => widget.onSuccess?.call(),
          ),
        )
      ],
    );
  }

  Widget fail(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                material.Icons.error_outline,
                color: material.Theme.of(context).colorScheme.error,
                size: 40,
              ),
            ),
            const tiamat.Text.largeTitle("Login failed...")
          ],
        ),
        SizedBox(
          height: 40,
          width: 200,
          child: tiamat.Button.danger(
            text: CommonStrings.promptContinue,
            onTap: () => widget.onFail?.call(),
          ),
        )
      ],
    );
  }
}
