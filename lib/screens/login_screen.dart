import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  final bool isDriver;
  const LoginScreen({super.key, required this.isDriver});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _pass = TextEditingController(), _adm = TextEditingController();
  final _passFocus = FocusNode(), _emailFocus = FocusNode();
  bool _register = false, _busy = false, _hide = true, _remember = true, _admin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Session.lastEmail().then((e) {
      if (e != null && mounted && _email.text.isEmpty) _email.text = e;
    });
  }

  @override
  void dispose() {
    _email.dispose(); _pass.dispose(); _adm.dispose(); _passFocus.dispose(); _emailFocus.dispose();
    super.dispose();
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email': return 'That email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials': return 'Wrong email or password.';
      case 'email-already-in-use': return 'This email already has an account. Try logging in.';
      case 'weak-password': return 'Password must be at least 6 characters.';
      case 'network-request-failed': return 'No internet connection.';
      case 'too-many-requests': return 'Too many attempts. Please wait and try again.';
      case 'user-disabled': return 'This account has been disabled.';
      default: return e.message ?? 'Something went wrong (${e.code}).';
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final auth = FirebaseAuth.instance;
    final email = _email.text.trim();
    try {
      if (_register && !widget.isDriver && !_admin) {
        // Activation, not open sign-up: only students the institution has registered (email + admission number)
        // get a profile. Anyone else is removed again right away.
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: _pass.text);
        try {
          await Repo.ensureStudentProfile(admissionNo: _adm.text);
        } catch (e) {
          try { await cred.user!.delete(); } catch (_) { await auth.signOut(); }
          if (e is NotAuthorized) throw e.message;
          if (e is FirebaseException && e.code == 'permission-denied') {
            throw 'This email / admission number is not registered by the institution.';
          }
          rethrow;
        }
        await Session.setRole(cred.user!.uid, 'student');
      } else {
        final cred = await auth.signInWithEmailAndPassword(email: email, password: _pass.text);
        final uid = cred.user!.uid;
        final staff = (await db.doc('app2_users/$uid').get()).data();
        final isStaff = staff != null;
        final isAdminAcct = (staff?['role'] ?? '').toString().toLowerCase() == 'admin';
        if (_admin && !isAdminAcct) {
          await auth.signOut();
          throw 'This is not an institution administrator account.';
        }
        if (!_admin && widget.isDriver && (!isStaff || isAdminAcct)) {
          await auth.signOut();
          throw isAdminAcct ? 'This is an institution account. Use "Institution login" below.' : 'This account is not a driver account. Ask the admin to add it.';
        }
        if (!_admin && !widget.isDriver && isStaff) {
          await auth.signOut();
          throw isAdminAcct ? 'This is an institution account. Use "Institution login" below.' : 'This is a driver account. Please use Driver Login.';
        }
        await Session.setRole(uid, _admin ? 'admin' : (widget.isDriver ? 'driver' : 'student'));
        if (!_admin && !widget.isDriver) {
          try {
            await Repo.ensureStudentProfile();
          } on NotAuthorized catch (e) {
            await auth.signOut();
            throw e.message;
          }
        }
      }
      await Session.setLastEmail(_remember ? email : null);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst); // AuthGate shows the home panel
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } on FirebaseException catch (e) {
      if (mounted) setState(() => _error = 'Database error (${e.code}). Check the Firestore rules are published.');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above first, then tap "Forgot password?".');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password reset email sent to $email')));
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: kInk.o(.55)),
        prefixIcon: Icon(icon, size: 20, color: kInk.o(.7)),
        suffixIcon: suffix,
        fillColor: Colors.white.o(.07),
        errorStyle: const TextStyle(color: Color(0xFFFF9D96)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.o(.18))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kYellow, width: 1.3)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFFF9D96))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFFF9D96), width: 1.3)),
      );

  @override
  Widget build(BuildContext context) {
    final driver = widget.isDriver || _admin;
    final reg = _register && !driver;
    const cream = TextStyle(color: kInk);
    return Scaffold(
      backgroundColor: kNavy,
      body: Stack(children: [
        Positioned.fill(child: Image.asset('assets/images/bus_sunset.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 1000)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kNavy.o(.55), kNavy.o(.82), kNavy.o(.98)], stops: const [0, .35, .7]),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Form(
                    key: _form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Align(alignment: Alignment.centerLeft, child: CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.maybePop(context))),
                      SizedBox(height: box.maxHeight * .2),
                      Text(_admin ? 'Institution login' : (widget.isDriver ? 'Driver login' : (reg ? 'Activate account' : 'Welcome back')), style: serif(38, height: 1.05)),
                      const SizedBox(height: 6),
                      Text(
                        _admin ? 'Manage students, buses, fees and reports.' : (widget.isDriver ? 'Sign in to share your live bus location.' : (reg ? 'Use the email and admission number registered with the institution.' : 'Sign in to track your college bus.')),
                        style: TextStyle(color: kInk.o(.75)),
                      ),
                      const SizedBox(height: 26),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: reg
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextFormField(
                                  controller: _adm,
                                  style: cream,
                                  cursorColor: kYellow,
                                  textCapitalization: TextCapitalization.characters,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your admission number' : null,
                                  decoration: _dec('Admission number', Icons.badge_outlined),
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      TextFormField(
                        controller: _email,
                        focusNode: _emailFocus,
                        style: cream,
                        cursorColor: kYellow,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _passFocus.requestFocus(),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                        decoration: _dec('Email', Icons.mail_outline),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pass,
                        focusNode: _passFocus,
                        style: cream,
                        cursorColor: kYellow,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                        decoration: _dec(
                          'Password',
                          Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: kInk.o(.7)),
                            onPressed: () => setState(() => _hide = !_hide),
                          ),
                        ),
                      ),
                      if (!reg)
                        Row(children: [
                          Checkbox(
                            value: _remember,
                            activeColor: kYellow,
                            checkColor: kOnGold,
                            side: BorderSide(color: kInk.o(.6), width: 1.5),
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) => setState(() => _remember = v ?? true),
                          ),
                          Text('Remember me', style: TextStyle(fontSize: 13, color: kInk.o(.85))),
                          const Spacer(),
                          TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?', style: TextStyle(color: kYellow, fontSize: 13))),
                        ])
                      else
                        const SizedBox(height: 10),
                      if (_error != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: kRed.o(.18), borderRadius: BorderRadius.circular(14), border: Border.all(color: kRed.o(.6))),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Color(0xFFFF9D96), size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13.5))),
                          ]),
                        ),
                      const SizedBox(height: 4),
                      GradientButton(label: reg ? 'Activate account' : 'Login', busy: _busy, onPressed: _submit),
                      if (!driver)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(reg ? 'Already activated? ' : 'First time here? ', style: TextStyle(color: kInk.o(.7), fontSize: 13.5)),
                            GestureDetector(
                              onTap: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
                              child: Text(reg ? 'Log in' : 'Activate account', style: const TextStyle(color: kYellow, fontWeight: FontWeight.w800, fontSize: 13.5)),
                            ),
                          ]),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: TextButton(
                            onPressed: _busy ? null : () => setState(() { _admin = !_admin; _register = false; _error = null; }),
                            child: Text(_admin ? 'Back to normal login' : 'Institution login', style: TextStyle(color: kInk.o(.7), fontSize: 13)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
