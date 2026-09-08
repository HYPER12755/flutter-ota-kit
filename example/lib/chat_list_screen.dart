import 'package:flutter/material.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  static const _chats = <_Chat>[
    _Chat('Alice', 'Hey, how are you?', '2m', Colors.blue, Icons.person),
    _Chat('Bob', 'Did you see the game?', '15m', Colors.green, Icons.sports_esports),
    _Chat('Charlie', 'Meeting at 3pm tomorrow', '1h', Colors.orange, Icons.work),
    _Chat('Diana', 'Thanks for the help!', '3h', Colors.purple, Icons.star),
    _Chat('Eve', 'Happy birthday!', '5h', Colors.pink, Icons.cake),
    _Chat('Frank', 'Sent you the files', '8h', Colors.teal, Icons.folder),
    _Chat('Grace', 'See you soon!', '1d', Colors.red, Icons.waving_hand),
    _Chat('Hank', 'Great job on the project', '2d', Colors.indigo, Icons.thumb_up),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: chat.color,
              radius: 24,
              child: Icon(chat.icon, color: Colors.white, size: 22),
            ),
            title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(chat.lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(chat.time, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(name: chat.name, color: chat.color),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Chat {
  final String name, lastMsg, time;
  final Color color;
  final IconData icon;
  const _Chat(this.name, this.lastMsg, this.time, this.color, this.icon);
}
