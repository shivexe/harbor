import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../security_gate.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final input = TextEditingController();
  bool scanning = false;
  bool returned = false;
  void accept(String code) {
    if (!returned) {
      returned = true;
      Navigator.pop(context, code);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair desktop')),
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bring your hosts aboard.',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Open pairing in Harbor on your desktop. Scan its QR code or paste the pairing code below.',
                style: TextStyle(color: Color(0xffa1b1cb), height: 1.5),
              ),
              const SizedBox(height: 24),
              if (scanning)
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: MobileScanner(
                      onDetect: (capture) {
                        final value = capture.barcodes.firstOrNull?.rawValue;
                        if (value != null) accept(value);
                      },
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => scanning = true),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR code'),
                ),
              const SizedBox(height: 24),
              TextField(
                onChanged: (_) => noteInteraction(),
                controller: input,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'Paste pairing code',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (input.text.trim().isNotEmpty) accept(input.text.trim());
                },
                child: const Text('Pair desktop'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
