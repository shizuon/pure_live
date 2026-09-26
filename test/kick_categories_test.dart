
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/kick/kick_site.dart';
import 'package:pure_live/modules/areas/kick_areas_page.dart';

class _Kick extends KickSite {
  final calls = <int>[];
  bool fail = false;
  int? returnedPage;
  @override
  Future<dynamic> request(String path, {Map<String, dynamic>? query}) async {
    final page = query!['page'] as int;
    calls.add(page);
    if (fail) throw StateError('offline');
    return {
      'current_page': returnedPage ?? page,
      'per_page': 32,
      'total': 12964,
      'last_page': 406,
      'next_page_url': 'https://kick.com/api/v1/subcategories?page=${page + 1}',
      'data': List.generate(
        32,
        (i) => {
          'id': (page - 1) * 32 + i,
          'name': 'Category $i',
          'slug': 'category-${(page - 1) * 32 + i}',
          'category': {'id': 1, 'name': 'Games'},
          'banner': null,
        },
      ),
    };
  }
}

class _Controller extends KickAreasController {
  _Controller(super.site);
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
  @override
  void handleError(Object exception, {bool showPageError = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('catalogue requests only one server page even with 406 pages advertised', () async {
    final site = _Kick();
    final groups = await site.getCategores(1, 1000);
    expect(site.calls, [1]);
    expect(groups.single.children, hasLength(32));
    expect(groups.single.children.first.shortName, 'category-0');
    await site.getCategores(406, 1000);
    expect(site.calls, [1, 406]);
  });
  test('unexpected echoed page errors rather than repeating the first page forever', () async {
    final site = _Kick()..returnedPage = 1;
    await expectLater(site.getCategores(2, 32), throwsStateError);
  });
  test('desktop next/back and refresh request bounded slices, not entire catalogue', () async {
    final site = _Kick();
    final c = _Controller(site);
    addTearDown(c.onClose);
    c.checkAndNotifyLayoutChange(true);
    c.pageSize.value = 20;
    await c.loadData();
    expect(site.calls, [1]);
    expect(c.list, hasLength(20));
    await c.goToPage(2);
    expect(site.calls, [1, 2]);
    expect(c.list.first.areaId, '20');
    expect(c.list.last.areaId, '39');
    await c.goToPage(1);
    expect(site.calls, [1, 2]);
    expect(c.list.first.areaId, '0');
    await c.refreshData();
    expect(site.calls, [1, 2, 1]);
    expect(c.list, hasLength(20));
  });
  test('mobile appends pages and refresh replaces rather than duplicating', () async {
    final site = _Kick();
    final c = _Controller(site);
    addTearDown(c.onClose);
    c.checkAndNotifyLayoutChange(false);
    c.pageSize.value = 20;
    await c.refreshData();
    await c.loadMoreData();
    expect(c.list, hasLength(40));
    expect(c.list.map((a) => a.areaId).toSet(), hasLength(40));
    await c.refreshData();
    expect(c.list, hasLength(20));
    expect(c.list.first.areaId, '0');
  });
  test('failed next page keeps current page and retries the missing slice', () async {
    final site = _Kick();
    final c = _Controller(site);
    addTearDown(c.onClose);
    c.checkAndNotifyLayoutChange(true);
    c.pageSize.value = 20;
    await c.loadData();
    site.fail = true;
    await c.goToPage(2);
    expect(c.currentPage, 1);
    expect(c.list.first.areaId, '0');
    site.fail = false;
    await c.goToPage(2);
    expect(c.currentPage, 2);
    expect(c.list.first.areaId, '20');
    expect(site.calls, [1, 2, 2]);
  });
}
