import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/presentation/widgets/account_section.dart';
import 'package:opensplit/presentation/widgets/identity_choices.dart';

final _guest = Account(
  id: 'guest',
  isAnonymous: true,
  email: null,
  displayName: null,
);

void main() {
  for (final linking in [false, true]) {
    testWidgets(
      '${linking ? 'account linking' : 'sign-in'} accepts an eight-digit code',
      (tester) async {
        final controller = _EmailController(
          linking ? EmailFlow.linkPending : EmailFlow.signInPending,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountControllerProvider.overrideWith(() => controller),
              accountProvider.overrideWith((ref) => Stream.value(_guest)),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: linking
                      ? const AccountSection()
                      : const IdentityChoices(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'person@example.com',
        );
        await tester.tap(
          find.text(linking ? 'Send me a code' : 'Continue with email'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Eight-digit code'), findsOneWidget);
        expect(find.text('Six-digit code'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, 'Eight-digit code'),
          '01234567',
        );
        await tester.tap(find.text('Verify code'));
        await tester.pumpAndSettle();

        expect(controller.recorded.email, 'person@example.com');
        expect(controller.recorded.code, '01234567');
        expect(controller.recorded.verifiedFlow, controller.flow);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// What [_EmailController] was asked to do, kept off the notifier itself.
class _Recorded {
  String? email;
  String? code;
  EmailFlow? verifiedFlow;
}

class _EmailController extends AccountController {
  _EmailController(this.flow);

  final EmailFlow flow;
  final _Recorded recorded = _Recorded();

  @override
  Future<EmailFlow> sendEmailCode(String email) async => flow;

  @override
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    recorded
      ..email = email
      ..code = code
      ..verifiedFlow = flow;
    return SessionKept(account: _guest);
  }
}
