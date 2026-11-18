import 'package:opensplit/domain/settle/reminder.dart';
import 'package:test/test.dart';

void main() {
  test('names the amount and the group', () {
    expect(
      reminderText(
        debtorName: 'Brinda',
        amount: '₹4,761.80',
        groupName: 'Goa trip',
      ),
      'Hi Brinda, a reminder from OpenSplit: you owe me ₹4,761.80 in '
      '“Goa trip”.',
    );
  });

  test('says where to pay when the sender has a UPI ID', () {
    expect(
      reminderText(
        debtorName: 'Brinda',
        amount: '₹50.00',
        groupName: 'Flat',
        upiVpa: ' ana@okbank ',
      ),
      endsWith('“Flat”. You can pay me by UPI at ana@okbank.'),
    );
  });
}
