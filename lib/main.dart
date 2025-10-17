import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

// ЗАМЕНИТЕ на ваш IP/домен (например, https://xxx.ngrok.io)
const String backendBase = "http://YOUR_PC_IP_OR_TUNNEL:8000";

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taxi Bid',
      theme: ThemeData(useMaterial3: true),
      home: const RoleSelectPage(),
    );
  }
}

class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Taxi Bid – выбор роли')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PassengerPage()),
            ),
            child: const Text('Я пассажир'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverPage()),
            ),
            child: const Text('Я водитель'),
          ),
        ]),
      ),
    );
  }
}

// ===== Пассажир =====
class PassengerPage extends StatefulWidget {
  const PassengerPage({super.key});
  @override
  State<PassengerPage> createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  int? requestId;
  List offers = [];
  Timer? timer;

  Future<void> createRequest() async {
    final url = Uri.parse("$backendBase/requests");
    final resp = await http.post(url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "pickup": _fromCtrl.text,
          "dropoff": _toCtrl.text,
          "passenger_name": _nameCtrl.text,
        }));
    if (!mounted) return;
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      setState(() => requestId = data['id']);
      startPollingOffers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка создана')),
      );
    } else {
      showError('Ошибка создания заявки: ${resp.body}');
    }
  }

  void startPollingOffers() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (requestId == null) return;
      final url = Uri.parse("$backendBase/requests/$requestId/offers");
      final resp = await http.get(url);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => offers = jsonDecode(resp.body));
      }
    });
  }

  Future<void> acceptOffer(int offerId) async {
    final url = Uri.parse("$backendBase/requests/$requestId/accept");
    final resp = await http.post(url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"offer_id": offerId}));
    if (!mounted) return;
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Предложение принято!')),
      );
    } else {
      showError('Не удалось принять: ${resp.body}');
    }
  }

  void showError(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));

  @override
  void dispose() {
    timer?.cancel();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пассажир')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Имя (необязательно)')),
          TextField(controller: _fromCtrl, decoration: const InputDecoration(labelText: 'Откуда')),
          TextField(controller: _toCtrl, decoration: const InputDecoration(labelText: 'Куда')),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: createRequest, child: const Text('Создать заявку')),
          const Divider(height: 32),
          if (requestId != null) ...[
            Text('Заявка №$requestId', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Предложения водителей:'),
            const SizedBox(height: 8),
            for (var o in offers)
              Card(
                child: ListTile(
                  title: Text('${o['driver_name']} — ${o['price']} ₽'),
                  subtitle: Text('Минут до подъезда: ${o['eta_minutes']} | статус: ${o['status']}'),
                  trailing: ElevatedButton(
                    onPressed: o['status'] == 'pending' ? () => acceptOffer(o['id']) : null,
                    child: const Text('Выбрать'),
                  ),
                ),
              ),
          ]
        ]),
      ),
    );
  }
}

// ===== Водитель =====
class DriverPage extends StatefulWidget {
  const DriverPage({super.key});
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  final _nameCtrl = TextEditingController();
  List requests = [];
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => loadOpenRequests());
    loadOpenRequests();
  }

  Future<void> loadOpenRequests() async {
    final url = Uri.parse("$backendBase/requests?status=open");
    final resp = await http.get(url);
    if (!mounted) return;
    if (resp.statusCode == 200) {
      setState(() => requests = jsonDecode(resp.body));
    }
  }

  Future<void> sendOffer(int requestId) async {
    final driverName = _nameCtrl.text.isEmpty ? 'Водитель' : _nameCtrl.text;
    final priceCtrl = TextEditingController();
    final etaCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Отправить предложение'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Цена'), keyboardType: TextInputType.number),
            TextField(controller: etaCtrl, decoration: const InputDecoration(labelText: 'Минут до подъезда'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отправить')),
        ],
      ),
    );

    if (ok != true) return;

    final url = Uri.parse("$backendBase/offers");
    final resp = await http.post(url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "request_id": requestId,
          "driver_name": driverName,
          "price": double.tryParse(priceCtrl.text) ?? 0,
          "eta_minutes": int.tryParse(etaCtrl.text) ?? 0,
        }));
    if (!mounted) return;
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предложение отправлено')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${resp.body}'), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Водитель')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Ваше имя')),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: loadOpenRequests,
              child: ListView.builder(
                itemCount: requests.length,
                itemBuilder: (ctx, i) {
                  final r = requests[i];
                  return Card(
                    child: ListTile(
                      title: Text('Откуда: ${r['pickup']}'),
                      subtitle: Text('Куда: ${r['dropoff']} | Заявка №${r['id']}'),
                      trailing: ElevatedButton(
                        onPressed: () => sendOffer(r['id']),
                        child: const Text('Предложить'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
