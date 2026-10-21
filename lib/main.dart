import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MeriShopApp());

// ---------------- utils ----------------
String uid() =>
    '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${(DateTime.now().microsecond % 46656).toRadixString(36)}';

String rs(num n) {
  final s = n.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final pos = s.length - i;
    buf.write(s[i]);
    if (pos > 1 && pos % 3 == 1) buf.write(',');
  }
  return 'Rs ${buf.toString()}';
}

String todayStr() => DateTime.now().toIso8601String().substring(0, 10);

String dstr(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  int h = d.hour;
  final ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '${d.day} ${months[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

String todayLine() {
  final d = DateTime.now();
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}

// ---------------- database ----------------
class DB {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> txns = [];

  static Future<DB> load() async {
    final p = await SharedPreferences.getInstance();
    final db = DB();
    final raw = p.getString('shopDB');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      db.products = List<Map<String, dynamic>>.from(m['products'] ?? []);
      db.customers = List<Map<String, dynamic>>.from(m['customers'] ?? []);
      db.sales = List<Map<String, dynamic>>.from(m['sales'] ?? []);
      db.txns = List<Map<String, dynamic>>.from(m['txns'] ?? []);
    }
    return db;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'shopDB',
        jsonEncode({
          'products': products,
          'customers': customers,
          'sales': sales,
          'txns': txns,
        }));
  }

  Map<String, num> bal(String cid) {
    num given = 0, paid = 0;
    for (final t in txns) {
      if (t['customerId'] == cid) {
        if (t['type'] == 'udhaar') {
          given += (t['amount'] as num);
        } else {
          paid += (t['amount'] as num);
        }
      }
    }
    final b = given - paid;
    return {'given': given, 'paid': paid, 'bal': b < 0 ? 0 : b};
  }
}

// ---------------- app shell ----------------
class MeriShopApp extends StatelessWidget {
  const MeriShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meri Shop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7A3D)),
        useMaterial3: true,
      ),
      home: const MainTabs(),
    );
  }
}

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});
  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;
  DB? _db;

  @override
  void initState() {
    super.initState();
    DB.load().then((db) => setState(() => _db = db));
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (_db == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final db = _db!;
    final screens = [
      HomeScreen(db: db, refresh: _refresh),
      SaleScreen(db: db, refresh: _refresh),
      KhataScreen(db: db, refresh: _refresh),
      StockScreen(db: db, refresh: _refresh),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏪 Meri Shop', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1B7A3D),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(todayLine(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ),
      ),
      body: screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1B7A3D),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Hisab'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Frokht'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Khata'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Stock'),
        ],
      ),
    );
  }
}

Widget statCard(String label, String value, Color color) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    ),
  );
}

// ---------------- HOME ----------------
class HomeScreen extends StatelessWidget {
  final DB db;
  final VoidCallback refresh;
  const HomeScreen({super.key, required this.db, required this.refresh});

  @override
  Widget build(BuildContext context) {
    final t = todayStr();
    final m = t.substring(0, 7);
    num td = 0, mo = 0;
    for (final s in db.sales) {
      if (s['date'] == t) td += (s['total'] as num);
      if ((s['date'] as String).startsWith(m)) mo += (s['total'] as num);
    }
    num udh = 0;
    for (final c in db.customers) {
      udh += db.bal(c['id'] as String)['bal']!;
    }
    final low = db.products.where((p) => (p['qty'] as num) <= 5).length;
    final todays = db.sales.where((s) => s['date'] == t).toList().reversed.take(10).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: [
            statCard('Aaj ki Sale', rs(td), const Color(0xFF1B7A3D)),
            statCard('Is Mahine ki Sale', rs(mo), const Color(0xFF1B7A3D)),
            statCard('Kul Udhaar', rs(udh), Colors.red),
            statCard('Low Stock', '$low', Colors.orange),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Aaj ki Frokht', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B7A3D))),
        ),
        Card(
          child: todays.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Aaj koi sale nahi hui', style: TextStyle(color: Colors.grey))))
              : Column(
                  children: todays.map((s) {
                    final items = (s['items'] as List).map((i) => "${i['name']} x${i['qty']}").join(', ');
                    return ListTile(
                      title: Text(items, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(dstr(s['ts'] as int), style: const TextStyle(fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(rs(s['total'] as num),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B7A3D))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: s['type'] == 'cash' ? Colors.green[50] : Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(s['type'] == 'cash' ? 'Cash' : 'Udhaar',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: s['type'] == 'cash' ? Colors.green[800] : Colors.red[800])),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

// ---------------- SALE ----------------
class SaleScreen extends StatefulWidget {
  final DB db;
  final VoidCallback refresh;
  const SaleScreen({super.key, required this.db, required this.refresh});
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  String? _pid;
  int _qty = 1;
  bool _isCash = true;
  String? _cid;
  final List<Map<String, dynamic>> _cart = [];

  DB get db => widget.db;

  void _addToCart() {
    if (_pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle product chunein')));
      return;
    }
    final p = db.products.firstWhere((e) => e['id'] == _pid);
    if ((p['qty'] as num) < _qty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Stock mein sirf ${p['qty']} hai")));
      return;
    }
    setState(() {
      _cart.add({'pid': p['id'], 'name': p['name'], 'qty': _qty, 'price': p['price']});
      _pid = null;
      _qty = 1;
    });
  }

  num get _total => _cart.fold<num>(0, (s, i) => s + (i['price'] as num) * (i['qty'] as num));

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart khali hai')));
      return;
    }
    if (!_isCash && _cid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Udhaar ke liye customer chunein')));
      return;
    }
    for (final i in _cart) {
      final p = db.products.firstWhere((e) => e['id'] == i['pid']);
      p['qty'] = (p['qty'] as num) - (i['qty'] as num);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final total = _total;
    db.sales.add({
      'id': uid(),
      'ts': ts,
      'date': todayStr(),
      'items': _cart.map((i) => {'pid': i['pid'], 'name': i['name'], 'qty': i['qty'], 'price': i['price']}).toList(),
      'total': total,
      'type': _isCash ? 'cash' : 'udhaar',
      'customerId': _isCash ? null : _cid,
    });
    if (!_isCash) {
      db.txns.add({
        'id': uid(),
        'customerId': _cid,
        'ts': ts,
        'type': 'udhaar',
        'amount': total,
        'note': 'Sale: ${_cart.map((i) => "${i['name']} x${i['qty']}").join(', ')}',
        'items': _cart.map((i) => {'name': i['name'], 'qty': i['qty'], 'price': i['price']}).toList(),
      });
    }
    await db.save();
    setState(() {
      _cart.clear();
      _cid = null;
      _isCash = true;
    });
    widget.refresh();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('✅ Sale save ho gayi: ${rs(total)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nayi Sale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B7A3D))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _pid,
                  hint: const Text('Product chunein'),
                  items: db.products
                      .map((p) => DropdownMenuItem<String>(
                            value: p['id'] as String,
                            child: Text("${p['name']} (${rs(p['price'] as num)}) — Stock: ${p['qty']}"),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _pid = v),
                ),
                Row(
                  children: [
                    const Text('Qty: '),
                    IconButton(icon: const Icon(Icons.remove), onPressed: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1)),
                    Text('$_qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _qty++)),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _addToCart,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Cart mein'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A3D), foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_cart.isNotEmpty)
          Card(
            child: Column(
              children: [
                ..._cart.asMap().entries.map((e) {
                  final i = e.value;
                  return ListTile(
                    title: Text("${i['name']} x${i['qty']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(rs((i['price'] as num) * (i['qty'] as num))),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => setState(() => _cart.removeAt(e.key)),
                        ),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kul:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(rs(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B7A3D))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('💵 Cash'),
                      selected: _isCash,
                      onSelected: (_) => setState(() => _isCash = true),
                      selectedColor: Colors.green[100],
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('📒 Udhaar'),
                      selected: !_isCash,
                      onSelected: (_) => setState(() => _isCash = false),
                      selectedColor: Colors.red[100],
                    ),
                  ],
                ),
                if (!_isCash)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: _cid,
                      hint: const Text('Customer chunein'),
                      items: db.customers
                          .map((c) => DropdownMenuItem<String>(value: c['id'] as String, child: Text(c['name'] as String)))
                          .toList(),
                      onChanged: (v) => setState(() => _cid = v),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveSale,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B7A3D), foregroundColor: Colors.white, padding: const EdgeInsets.all(14)),
                    child: const Text('✅ Sale Save Karo', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- KHATA ----------------
class KhataScreen extends StatefulWidget {
  final DB db;
  final VoidCallback refresh;
  const KhataScreen({super.key, required this.db, required this.refresh});
  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  DB get db => widget.db;

  Future<void> _addCustomer() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Naya Customer'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Naam'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      db.customers.add({'id': uid(), 'name': name});
      await db.save();
      setState(() {});
      widget.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...db.customers];
    sorted.sort((a, b) => (db.bal(b['id'] as String)['bal']!).compareTo(db.bal(a['id'] as String)['bal']!));
    return Scaffold(
      body: sorted.isEmpty
          ? const Center(child: Text('Koi customer nahi hai', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) {
                final c = sorted[i];
                final b = db.bal(c['id'] as String);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1B7A3D),
                      child: Text((c['name'] as String).substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text("Kul Udhaar: ${rs(b['given']!)} • Kul Jama: ${rs(b['paid']!)}",
                        style: const TextStyle(fontSize: 12)),
                    trailing: Text(rs(b['bal']!),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: (b['bal']! as num) > 0 ? Colors.red : Colors.green)),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CustomerDetail(db: db, cid: c['id'] as String, name: c['name'] as String)),
                      );
                      setState(() {});
                      widget.refresh();
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCustomer,
        backgroundColor: const Color(0xFF1B7A3D),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}

class CustomerDetail extends StatefulWidget {
  final DB db;
  final String cid;
  final String name;
  const CustomerDetail({super.key, required this.db, required this.cid, required this.name});
  @override
  State<CustomerDetail> createState() => _CustomerDetailState();
}

class _CustomerDetailState extends State<CustomerDetail> {
  DB get db => widget.db;

  Future<void> _addTxn(String type) async {
    final amtC = TextEditingController();
    final noteC = TextEditingController();
    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'udhaar' ? 'Udhaar Likho' : 'Jama Karo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amtC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Raqam (Rs)'), autofocus: true),
            TextField(controller: noteC, decoration: const InputDecoration(labelText: 'Tafseel / Note')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {'amt': amtC.text.trim(), 'note': noteC.text.trim()}),
              child: const Text('Save')),
        ],
      ),
    );
    if (res != null) {
      final amt = num.tryParse(res['amt'] ?? '') ?? 0;
      if (amt > 0) {
        db.txns.add({
          'id': uid(),
          'customerId': widget.cid,
          'ts': DateTime.now().millisecondsSinceEpoch,
          'type': type,
          'amount': amt,
          'note': res['note'] ?? '',
        });
        await db.save();
        setState(() {});
      }
    }
  }

  Future<void> _shareStatement() async {
    final b = db.bal(widget.cid);
    final list = db.txns.where((t) => t['customerId'] == widget.cid).toList()
      ..sort((a, b2) => (a['ts'] as int).compareTo(b2['ts'] as int));
    final buf = StringBuffer();
    buf.writeln('📒 *${widget.name} ka Hisab*');
    buf.writeln('--------------------------');
    for (final t in list) {
      final sign = t['type'] == 'udhaar' ? '-' : '+';
      final dt = dstr(t['ts'] as int);
      var line = '$dt: $sign ${rs(t['amount'] as num)}';
      final note = (t['note'] ?? '') as String;
      if (note.isNotEmpty) line += ' ($note)';
      final items = t['items'] as List?;
      if (items != null && items.isNotEmpty) {
        line += '\n   ${items.map((i) => "${i['name']} x${i['qty']}").join(', ')}';
      }
      buf.writeln(line);
    }
    buf.writeln('--------------------------');
    buf.writeln('Kul Udhaar: ${rs(b['given']!)}');
    buf.writeln('Kul Jama: ${rs(b['paid']!)}');
    buf.writeln('*Baqi: ${rs(b['bal']!)}*');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hisab copy ho gaya — WhatsApp/Gmail mein paste karke bhejein 📋')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = db.bal(widget.cid);
    final list = db.txns.where((t) => t['customerId'] == widget.cid).toList()
      ..sort((a, bb) => (bb['ts'] as int).compareTo(a['ts'] as int));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1B7A3D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(child: statCard('Kul Udhaar', rs(b['given']!), Colors.red)),
              Expanded(child: statCard('Kul Jama', rs(b['paid']!), Colors.green)),
            ],
          ),
          statCard('Baqi (Dena hai)', rs(b['bal']!), (b['bal']! as num) > 0 ? Colors.red : Colors.green),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _addTxn('udhaar'),
                  icon: const Icon(Icons.add),
                  label: const Text('Udhaar'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _addTxn('payment'),
                  icon: const Icon(Icons.check),
                  label: const Text('Jama'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B7A3D), foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareStatement,
                  icon: const Icon(Icons.share),
                  label: const Text('Hisab Bhejo'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Full History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B7A3D))),
          const SizedBox(height: 4),
          Card(
            child: list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('Koi entry nahi', style: TextStyle(color: Colors.grey))))
                : Column(
                    children: list.map((t) {
                      final isU = t['type'] == 'udhaar';
                      final items = t['items'] as List?;
                      return ListTile(
                        leading: Icon(isU ? Icons.arrow_upward : Icons.arrow_downward,
                            color: isU ? Colors.red : Colors.green),
                        title: Text(
                          '${isU ? '-' : '+'} ${rs(t['amount'] as num)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: isU ? Colors.red : Colors.green),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dstr(t['ts'] as int), style: const TextStyle(fontSize: 12)),
                            if (((t['note'] ?? '') as String).isNotEmpty)
                              Text(t['note'] as String, style: const TextStyle(fontSize: 13)),
                            if (items != null && items.isNotEmpty)
                              Text(items.map((i) => "${i['name']} x${i['qty']}").join(', '),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------- STOCK ----------------
class StockScreen extends StatefulWidget {
  final DB db;
  final VoidCallback refresh;
  const StockScreen({super.key, required this.db, required this.refresh});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  DB get db => widget.db;

  Future<void> _addProduct() async {
    final nC = TextEditingController();
    final pC = TextEditingController();
    final qC = TextEditingController();
    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Naya Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nC, decoration: const InputDecoration(labelText: 'Naam'), autofocus: true),
            TextField(controller: pC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qeemat (Rs)')),
            TextField(controller: qC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {'n': nC.text.trim(), 'p': pC.text.trim(), 'q': qC.text.trim()}),
              child: const Text('Add')),
        ],
      ),
    );
    if (res != null && res['n']!.isNotEmpty) {
      db.products.add({
        'id': uid(),
        'name': res['n']!,
        'price': num.tryParse(res['p'] ?? '') ?? 0,
        'qty': num.tryParse(res['q'] ?? '') ?? 0,
      });
      await db.save();
      setState(() {});
      widget.refresh();
    }
  }

  Future<void> _editQty(Map<String, dynamic> p) async {
    final qC = TextEditingController(text: '${p['qty']}');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p['name']} — Qty'),
        content: TextField(controller: qC, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, qC.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (res != null) {
      p['qty'] = num.tryParse(res) ?? p['qty'];
      await db.save();
      setState(() {});
      widget.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: db.products.isEmpty
          ? const Center(child: Text('Koi product nahi hai', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: db.products.length,
              itemBuilder: (ctx, i) {
                final p = db.products[i];
                final low = (p['qty'] as num) <= 5;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: low ? Colors.orange : const Color(0xFF1B7A3D),
                      child: const Icon(Icons.inventory, color: Colors.white),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (low)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(12)),
                            child: const Text('LOW', style: TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    subtitle: Text('${rs(p['price'] as num)} • Stock: ${p['qty']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Color(0xFF1B7A3D)),
                          onPressed: () => _editQty(p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete?'),
                                content: Text('${p['name']} delete kar dein?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Haan')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              db.products.removeAt(i);
                              await db.save();
                              setState(() {});
                              widget.refresh();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        backgroundColor: const Color(0xFF1B7A3D),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
