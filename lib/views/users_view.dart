import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../controllers/users_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/ui_feedback.dart';
import '../models/access_policy.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import 'widgets/common_widgets.dart';
import 'widgets/dialogs.dart';

/// Owner-only list of farm accounts.
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = UsersController();
    return Scaffold(
      appBar: AppBar(title: const Text('Users & roles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserFormPage())),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add user'),
      ),
      body: ListenableBuilder(
        listenable: c.auth,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 96), children: [
          const Text('Everyone who can sign in to this farm. Each role only sees the modules it needs.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          for (final role in UserRole.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Row(children: [
                Icon(role.icon, size: 18, color: AppColors.brand),
                const SizedBox(width: 6),
                Text(role.label, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(width: 6),
                Expanded(child: Text('· ${role.description}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              ]),
            ),
            ...c.users.where((u) => u.role == role).map((u) => _UserCard(user: u, isMe: c.isMe(u), controller: c)),
            if (!c.users.any((u) => u.role == role)) const Padding(padding: EdgeInsets.only(bottom: 8), child: EmptyHint('No accounts with this role yet.')),
          ],
        ]),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.isMe, required this.controller});

  final AppUser user;
  final bool isMe;
  final UsersController controller;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: user.active ? AppColors.brandSoft : const Color(0xFFEDEDED),
            child: Text(user.initials, style: TextStyle(color: user.active ? AppColors.brand : Colors.black45, fontWeight: FontWeight.bold)),
          ),
          title: Text('${user.name}${isMe ? ' (you)' : ''}', style: TextStyle(fontWeight: FontWeight.w700, color: user.active ? AppColors.ink : Colors.black45)),
          subtitle: Text([
            '@${user.username}',
            if (user.phone.isNotEmpty) user.phone,
            if (user.role == UserRole.manager) user.grants.isEmpty ? 'Operations only' : 'Also: ${ManagerGrant.values.where(user.grants.contains).map((g) => g.label.toLowerCase()).join(', ')}',
            if (!user.active) 'Disabled',
          ].join(' · ')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserFormPage(existing: user))),
          trailing: isMe
              ? null
              : IconButton(
                  tooltip: 'Delete user',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Delete ${user.name}?',
                        message: 'They will no longer be able to sign in. Their past activity stays in the log. To block access temporarily, disable the account instead.',
                        confirmLabel: 'Delete');
                    if (!ok) return;
                    final error = await controller.delete(user);
                    if (context.mounted) showToast(context, error ?? '${user.name} deleted');
                  },
                ),
        ),
      );
}

/// Add a new account, or edit name/role/status and reset the password.
class UserFormPage extends StatefulWidget {
  const UserFormPage({super.key, this.existing});

  final AppUser? existing;

  @override
  State<UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends State<UserFormPage> {
  late final controller = UserFormController(existing: widget.existing);
  bool _obscure = true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await controller.save();
    if (!ok || !mounted) return;
    showToast(context, controller.isEditing ? 'User updated' : 'User added');
    Navigator.pop(context);
  }

  Future<void> _resetPassword() async {
    final input = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset password for ${controller.existing!.name}'),
        content: TextField(
          controller: input,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New password', helperText: 'At least ${AuthController.minPasswordLength} characters. Share it with them privately.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, input.text), child: const Text('Reset password')),
        ],
      ),
    );
    input.dispose();
    if (newPassword == null || !mounted) return;
    final error = await controller.resetPassword(newPassword);
    if (mounted) showToast(context, error ?? 'Password reset');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(controller.title)),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Form(
            key: controller.formKey,
            child: ListView(padding: const EdgeInsets.all(18), children: [
              TextFormField(
                controller: controller.name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                validator: AuthController.validateName,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: controller.username,
                enabled: !controller.isEditing,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.alternate_email),
                  helperText: controller.isEditing ? 'Usernames cannot be changed' : 'Lowercase letters, numbers, dots or underscores',
                ),
                validator: controller.isEditing ? null : AuthController.validateUsername,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: controller.phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined)),
                validator: controller.validatePhone,
              ),
              if (!controller.isEditing) ...[
                const SizedBox(height: 13),
                TextFormField(
                  controller: controller.password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'At least ${AuthController.minPasswordLength} characters',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: AuthController.validatePassword,
                ),
              ],
              const SizedBox(height: 18),
              const Text('Role', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              ...UserRole.values.map((r) => RadioListTile<UserRole>(
                    value: r,
                    // ignore: deprecated_member_use
                    groupValue: controller.role,
                    // ignore: deprecated_member_use
                    onChanged: controller.isMe ? null : (v) => controller.setRole(v!),
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(r.icon, color: AppColors.brand),
                    title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(r.description),
                  )),
              if (controller.role == UserRole.manager) ...[
                const SizedBox(height: 10),
                const Text('What this manager may also do', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const Text('Daily operations (animals, feed, milk, health, breeding, stock) are always allowed. User accounts, settings, backup and deleting records stay with the owner.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                for (final g in ManagerGrant.values)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: controller.grants.contains(g),
                    onChanged: (v) => controller.setGrant(g, v ?? false),
                    title: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(g.description),
                  ),
              ],
              if (controller.isEditing)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.active,
                  onChanged: controller.isMe ? null : controller.setActive,
                  title: const Text('Account active', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(controller.isMe ? 'You cannot disable your own account' : 'Disabled accounts cannot sign in'),
                ),
              if (controller.error != null) ...[
                const SizedBox(height: 8),
                Text(controller.error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: controller.busy ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(controller.isEditing ? 'Save changes' : 'Create user'),
                ),
              ),
              if (controller.isEditing) ...[
                const SizedBox(height: 8),
                SizedBox(height: 46, child: OutlinedButton.icon(onPressed: _resetPassword, icon: const Icon(Icons.key_outlined), label: const Text('Reset password'))),
              ],
            ]),
          ),
        ),
      );
}
