import 'package:flutter/material.dart';

import '../controllers/login_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/user_role.dart';
import 'widgets/company_card.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final controller = LoginController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Form(
                  key: controller.formKey,
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 28), children: [
                    Row(children: [
                      Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(13)),
                          child: const Icon(Icons.agriculture, color: Colors.white, size: 25)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('DeshIT-BD', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
                          Text('Farm management', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    const Text('Welcome back', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 5),
                    const Text('Choose your role and sign in to continue.', style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 20),
                    const Text('Sign in as', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: UserRole.values.map(_roleChip).toList()),
                    const SizedBox(height: 10),
                    _RoleSummary(role: controller.role),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: controller.username,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                      validator: controller.validateUsername,
                    ),
                    const SizedBox(height: 13),
                    TextFormField(
                      controller: controller.password,
                      obscureText: controller.obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => controller.submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: controller.obscurePassword ? 'Show password' : 'Hide password',
                          onPressed: controller.toggleObscure,
                          icon: Icon(controller.obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: controller.validatePassword,
                    ),
                    if (controller.error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFFE9E5), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 20),
                          const SizedBox(width: 9),
                          Expanded(child: Text(controller.error!, style: const TextStyle(color: Color(0xFF8C1D18), fontSize: 13))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: controller.remember,
                      onChanged: (v) => controller.setRemember(v ?? false),
                      title: Text('Remember ${controller.role.label} sign-in on this device'),
                      subtitle: const Text('Filled in next time this role is chosen'),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: controller.busy ? null : controller.submit,
                        icon: controller.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.login),
                        label: Text(controller.busy ? 'Signing in…' : 'Sign in as ${controller.role.label}'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: controller.fillDemoAccount,
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                      label: Text('Use demo ${controller.role.label} account'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Demo prototype: accounts are stored on this device only. Connect a real authentication backend before release.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 18),
                    const CompanyCard(compact: true),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _roleChip(UserRole role) => ChoiceChip(
        avatar: Icon(role.icon, size: 18, color: controller.role == role ? AppColors.brand : Colors.black54),
        label: Text(role.label),
        selected: controller.role == role,
        showCheckmark: false,
        onSelected: (_) => controller.selectRole(role),
      );
}

class _RoleSummary extends StatelessWidget {
  const _RoleSummary({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(role.icon, color: AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(role.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(role.description, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ]),
      );
}
