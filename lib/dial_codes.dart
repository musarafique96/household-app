/// A country and its phone dial code.
class DialCode {
  final String code;
  final String country;
  const DialCode(this.code, this.country);
}

const String kDefaultDial = '+92';

const List<DialCode> kDialCodes = [
  DialCode('+92', 'Pakistan'),
  DialCode('+973', 'Bahrain'),
  DialCode('+966', 'Saudi Arabia'),
  DialCode('+971', 'UAE'),
  DialCode('+974', 'Qatar'),
  DialCode('+965', 'Kuwait'),
  DialCode('+968', 'Oman'),
  DialCode('+91', 'India'),
  DialCode('+880', 'Bangladesh'),
  DialCode('+44', 'UK'),
  DialCode('+1', 'USA / Canada'),
  DialCode('+61', 'Australia'),
  DialCode('+49', 'Germany'),
  DialCode('+60', 'Malaysia'),
  DialCode('+65', 'Singapore'),
  DialCode('+20', 'Egypt'),
  DialCode('+98', 'Iran'),
];

/// Splits a stored phone number into its dial code and the rest of the number.
({String code, String number}) splitPhone(String phone) {
  final byLength = [...kDialCodes]..sort((a, b) => b.code.length.compareTo(a.code.length));
  for (final c in byLength) {
    if (phone.startsWith(c.code)) {
      return (code: c.code, number: phone.substring(c.code.length));
    }
  }
  return (code: kDefaultDial, number: phone);
}

/// Builds the full number, for example +923001234567. A leading 0 typed for local format is dropped.
String fullPhone(String code, String typed) {
  final digits = typed.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+'), '');
  return digits.isEmpty ? '' : '$code$digits';
}
