import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A Material number field that follows derived values until manually edited.
///
/// Only text selection, composing text and focus live here. Financial values
/// and automatic/manual intent belong to the form. In-progress typing is never
/// overwritten by a recalculation; clearing becomes automatic on focus loss.
class RemainderField extends StatefulWidget {
  const RemainderField({
    super.key,
    required this.label,
    required this.memberName,
    required this.onChanged,
    required this.inputFormatters,
    this.manualText,
    this.automaticText,
    this.prefixText,
    this.suffixText,
    this.invalid = false,
  });

  final String label;
  final String memberName;
  final String? manualText;
  final String? automaticText;
  final String? prefixText;
  final String? suffixText;
  final bool invalid;
  final ValueChanged<String> onChanged;
  final List<TextInputFormatter> inputFormatters;

  @override
  State<RemainderField> createState() => _RemainderFieldState();
}

class _RemainderFieldState extends State<RemainderField> {
  late final _text = TextEditingController(text: _value);
  final _focus = FocusNode();
  bool _typing = false;

  String get _value => widget.manualText ?? widget.automaticText ?? '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant RemainderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset is an explicit action; clearing while typing is different and
    // must leave room to type a replacement without the number jumping back.
    final reset =
        oldWidget.manualText != null &&
        widget.manualText == null &&
        _text.text.isNotEmpty;
    if (reset) _typing = false;
    _refresh();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) {
      _typing = false;
      _refresh();
    }
  }

  void _refresh() {
    if (_focus.hasFocus && _typing || _text.text == _value) return;
    _text.value = TextEditingValue(
      text: _value,
      selection: TextSelection.collapsed(offset: _value.length),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    hint: widget.manualText == null
        ? 'Shares the remainder when other values change.'
        : 'Custom value. Stays fixed when other values change.',
    child: TextField(
      controller: _text,
      focusNode: _focus,
      selectAllOnFocus: true,
      onTapOutside: (_) => _focus.unfocus(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: widget.inputFormatters,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.automaticText == null ? '—' : null,
        errorText: widget.invalid ? 'Check value' : null,
        errorMaxLines: 2,
        isDense: true,
        prefixText: widget.prefixText,
        suffixText: widget.suffixText,
        suffixIcon: widget.manualText == null
            ? null
            : IconButton(
                tooltip: "Let ${widget.memberName}'s value adjust",
                icon: const Icon(Icons.push_pin_outlined, size: 18),
                onPressed: () => widget.onChanged(''),
              ),
      ),
      onChanged: (text) {
        _typing = true;
        widget.onChanged(text);
      },
    ),
  );
}
