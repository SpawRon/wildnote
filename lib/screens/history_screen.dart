import 'package:flutter/material.dart';
import 'login_screen.dart';

class HistoryScreen extends StatelessWidget {
  final bool isGuest;
  const HistoryScreen({super.key, required this.isGuest});

  void _logout(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('История', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                if (isGuest)
                  const Chip(label: Text('Гость', style: TextStyle(fontSize: 12))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Очистить всё'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _logout(context),
                    child: const Text('Выйти'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4, // Заглушка
              itemBuilder: (context, index) {
                // 0 - локально, 1 - отправлено, если гость - всегда локально
                bool isSynced = !isGuest && index % 2 != 0;

                return Card(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),
                    leading: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
                    title: Text('Растение №${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('23.11.2025 • 68.97, 33.07\nТочность: ±4м', style: const TextStyle(fontSize: 12)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSynced ? Icons.cloud_done : (isGuest ? Icons.save : Icons.schedule_send),
                          color: isSynced ? Colors.green : Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(height: 8),
                        const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}