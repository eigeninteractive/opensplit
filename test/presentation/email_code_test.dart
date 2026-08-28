import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/presentation/widgets/account_section.dart';
import 'package:opensplit/presentation/widgets/identity_choices.dart';

const _guest = Account(id: 'guest', isAnonymous: true);

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

        expect(controller.email, 'person@example.com');
        expect(controller.code, '01234567');
        expect(controller.verifiedFlow, controller.flow);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _EmailController extends AccountController {
  _EmailController(this.flow);

  final EmailFlow flow;
  String? email;
  String? code;
  EmailFlow? verifiedFlow;

  @override
  Future<EmailFlow> sendEmailCode(String email) async => flow;

  @override
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    this.email = email;
    this.code = code;
    verifiedFlow = flow;
    return const SessionKept(account: _guest);
  }
}
