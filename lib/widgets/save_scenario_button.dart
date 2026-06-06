import 'package:flutter/material.dart';

import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../main.dart' show isSpanishNotifier;

/// A "Save Scenario" button that pins the current calculator result.
///
/// - **Premium users**: shows a name-entry dialog before saving.
/// - **Free users**: saves immediately without a label (3 max pinned slots).
///
/// Language-aware per flavor: CA → French, US → Spanish, UK → English only.
class SaveScenarioButton extends StatefulWidget {
  /// Called when the user confirms the save. [label] is null for free users.
  final Future<void> Function(String? label) onSave;

  const SaveScenarioButton({super.key, required this.onSave});

  @override
  State<SaveScenarioButton> createState() => _SaveScenarioButtonState();
}

class _SaveScenarioButtonState extends State<SaveScenarioButton> {
  bool _saving = false;

  bool get _fr => FlavorConfig.isCA && isSpanishNotifier.value;
  bool get _es => FlavorConfig.isUS && isSpanishNotifier.value;

  Future<void> _handleTap() async {
    String? label;

    if (freemiumService.hasFullAccess) {
      label = await _showNameDialog();
      if (label == null) return;
      if (label.trim().isEmpty) label = null;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(label);
      if (!mounted) return;
      final named = label != null && label.isNotEmpty;
      final msg = _fr
          ? (named ? 'Scénario « $label » enregistré' : 'Scénario enregistré')
          : _es
              ? (named ? 'Escenario "$label" guardado' : 'Escenario guardado')
              : (named ? 'Scenario "$label" saved' : 'Scenario saved');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    final title = _fr
        ? 'Enregistrer le scénario'
        : (_es ? 'Guardar escenario' : 'Save Scenario');
    final hint = _fr
        ? 'Nom du scénario (facultatif)'
        : (_es ? 'Nombre del escenario (opcional)' : 'Scenario name (optional)');
    final cancel = _fr ? 'Annuler' : (_es ? 'Cancelar' : 'Cancel');
    final save = _fr ? 'Enregistrer' : (_es ? 'Guardar' : 'Save');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _fr
        ? 'Enregistrer le scénario'
        : (_es ? 'Guardar escenario' : 'Save Scenario');
    final saving = _fr ? 'Enregistrement…' : (_es ? 'Guardando…' : 'Saving…');
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : _handleTap,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bookmark_add_outlined, size: 18),
        label: Text(_saving ? saving : label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}
