/// Flask stores UTC. Legacy responses omitted the zone; never interpret those
/// as device-local time. Explicit offsets are respected and converted once.
DateTime? parseApiDateTime(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final text = value.trim();
  final hasZone = RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(text);
  return DateTime.tryParse(hasZone ? text : '${text}Z')?.toLocal();
}
