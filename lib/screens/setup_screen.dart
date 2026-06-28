import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../legal/privacy_policy.dart';
import '../main.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _birthDateController;
  late final TextEditingController _conditionsController;
  DateTime? _birthDate;
  DateTime? _privacyAcceptedAt;
  String _gender = 'Female';
  bool _privacyAccepted = false;
  bool _privacyPolicyShown = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<DozState>();
    _nameController = TextEditingController(text: state.userName);
    _weightController =
        TextEditingController(text: state.weight.toStringAsFixed(0));
    _heightController =
        TextEditingController(text: state.height.toStringAsFixed(0));
    final estimatedBirthDate = state.birthDate ?? _birthDateFromAge(state.age);
    _birthDate = estimatedBirthDate;
    _birthDateController =
        TextEditingController(text: _formatBirthDate(estimatedBirthDate));
    _conditionsController = TextEditingController(text: state.conditions);
    _gender = state.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _birthDateController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 24),
              const _SetupHero(),
              const SizedBox(height: 28),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name / ชื่อ'),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) return 'Required';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _BirthDateField(
                controller: _birthDateController,
                onTap: _selectBirthDate,
              ),
              const SizedBox(height: 12),
              _NumberField(
                  controller: _weightController,
                  label: 'Weight (kg) / น้ำหนัก'),
              const SizedBox(height: 12),
              _NumberField(
                  controller: _heightController,
                  label: 'Height (cm) / ส่วนสูง'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                dropdownColor: const Color(0xFF11141B),
                items: const ['Female', 'Male', 'Other']
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _gender = value ?? _gender),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _conditionsController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText:
                      'Underlying disease / medical conditions / โรคประจำตัว',
                ),
              ),
              const SizedBox(height: 12),
              _PrivacyPolicyAccept(
                accepted: _privacyAccepted,
                onChanged: _handlePrivacyAccepted,
                onShowPolicy: _openPrivacyPolicyFromLink,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _privacyAccepted ? _submit : null,
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final birthDate = _birthDate;
    if (birthDate == null) return;
    context.read<DozState>().completeSetup(
          newName: _nameController.text,
          newPrivacyPolicyAcceptedAt: _privacyAcceptedAt ?? DateTime.now(),
          newWeight: double.parse(_weightController.text),
          newHeight: double.parse(_heightController.text),
          newAge: _ageFromBirthDate(birthDate),
          newBirthDate: birthDate,
          newGender: _gender,
          newConditions: _conditionsController.text,
        );
  }

  Future<void> _handlePrivacyAccepted(bool? value) async {
    final accepted = value ?? false;
    if (!accepted) {
      setState(() {
        _privacyAccepted = false;
        _privacyAcceptedAt = null;
      });
      return;
    }

    if (!_privacyPolicyShown) {
      _privacyPolicyShown = true;
      final dialogAccepted = await showPrivacyPolicyDialog(context);
      if (!mounted) return;
      setState(() {
        _privacyAccepted = dialogAccepted;
        _privacyAcceptedAt = dialogAccepted ? DateTime.now() : null;
      });
      return;
    }

    setState(() {
      _privacyAccepted = true;
      _privacyAcceptedAt ??= DateTime.now();
    });
  }

  Future<bool> _openPrivacyPolicyFromLink() async {
    _privacyPolicyShown = true;
    final accepted = await showPrivacyPolicyDialog(context);
    if (!mounted) return accepted;
    if (accepted) {
      setState(() {
        _privacyAccepted = true;
        _privacyAcceptedAt = DateTime.now();
      });
    }
    return accepted;
  }

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? _birthDateFromAge(20),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF11141B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected == null) return;
    setState(() {
      _birthDate = selected;
      _birthDateController.text = _formatBirthDate(selected);
    });
  }

  DateTime _birthDateFromAge(int age) {
    final now = DateTime.now();
    return DateTime(now.year - age, now.month, now.day);
  }

  int _ageFromBirthDate(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hasNotHadBirthdayThisYear = now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day);
    if (hasNotHadBirthdayThisYear) age -= 1;
    return age.clamp(0, 120);
  }

  String _formatBirthDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _PrivacyPolicyAccept extends StatelessWidget {
  const _PrivacyPolicyAccept({
    required this.accepted,
    required this.onChanged,
    required this.onShowPolicy,
  });

  final bool accepted;
  final ValueChanged<bool?> onChanged;
  final Future<bool> Function() onShowPolicy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: accepted,
            onChanged: onChanged,
            activeColor: Colors.white,
            checkColor: Colors.black,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'I accept the ',
                  style: TextStyle(color: Colors.white, height: 1.35),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onShowPolicy,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      'Privacy Policy',
                      style: TextStyle(
                        color: Colors.white,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const Text(
                  ' and allow doz to use my health, BLE, and location data for monitoring.',
                  style: TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupHero extends StatelessWidget {
  const _SetupHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF232833)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF050608),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.watch_outlined,
              color: Color(0xFFEF4444),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'doz',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Set up your profile and start health monitoring',
                  style: TextStyle(color: Color(0xFFA7B0C0)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = num.tryParse(value ?? '');
        if (number == null || number <= 0) return 'Required';
        return null;
      },
    );
  }
}

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.controller,
    required this.onTap,
  });

  final TextEditingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: const InputDecoration(
        labelText: 'Birth date / วันเกิด',
        suffixIcon: Icon(Icons.calendar_month_outlined),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Required';
        }
        return null;
      },
    );
  }
}
