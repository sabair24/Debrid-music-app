/// The queue, in Firestore.
///
/// Split from `queue.dart` on purpose: the rules about claiming, leases and how often progress may
/// be written are the part worth testing, and they should not need a Firebase project to run.
library;

import 'firestore.dart';
import 'queue.dart';

class FirestoreQueue implements QueueBackend {
  FirestoreQueue({required this.db, required this.uid});

  final Firestore db;
  final String uid;

  String get _collection => 'users/$uid/queue';

  @override
  Future<List<QueueItem>> list() async {
    final docs = await db.list(_collection);
    final items = <QueueItem>[];
    for (final d in docs) {
      final item = QueueItem.fromFields(d.id, d.data);
      if (item != null) items.add(item);
    }
    // Time-ordered ids, so this is also request order.
    items.sort((a, b) => a.id.compareTo(b.id));
    return items;
  }

  @override
  Future<QueueItem?> get(String id) async {
    final doc = await db.get('$_collection/$id');
    return doc == null ? null : QueueItem.fromFields(doc.id, doc.data);
  }

  @override
  Future<void> put(QueueItem item) => db.set('$_collection/${item.id}', item.toFields());

  @override
  Future<void> patch(String id, Map<String, dynamic> fields) =>
      db.set('$_collection/$id', fields);

  @override
  Future<void> remove(String id) => db.delete('$_collection/$id');
}
