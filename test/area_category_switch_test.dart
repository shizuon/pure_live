import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';

class _CategoryFixtureSite extends LiveSite {
  int requests = 0;

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    requests++;
    return [
      LiveCategory(
        id: 'games',
        name: 'Games',
        children: [
          LiveArea(areaId: 'g1'),
          LiveArea(areaId: 'g2'),
        ],
      ),
      LiveCategory(
        id: 'music',
        name: 'Music',
        children: [LiveArea(areaId: 'm1')],
      ),
    ];
  }
}

void main() {
  for (final siteId in ['fixture', Sites.douyinSite]) {
    test('$siteId categories retain their groups and switch local slices in order', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final site = _CategoryFixtureSite();
      final controller = AreasListController(Site(id: siteId, name: 'Fixture', logo: '', liveSite: site));
      addTearDown(controller.onClose);

      final initial = await controller.fetchAllServerData();
      expect(initial.map((area) => area.areaId), ['g1', 'g2']);
      expect(controller.categories.map((category) => category.id), ['games', 'music']);
      controller.processLocalPaging();
      expect(controller.list.map((area) => area.areaId), ['g1', 'g2']);
      expect(controller.totalCount.value, 2);

      for (final index in [1, 0, 1, 0]) {
        controller.selectCategory(index);
        expect(controller.tabIndex.value, index);
        expect(controller.currentPage, 1);
        expect(controller.list.map((area) => area.areaId), index == 0 ? ['g1', 'g2'] : ['m1']);
        expect(controller.totalCount.value, index == 0 ? 2 : 1);
        expect(controller.loadding.value, isFalse);
      }
      expect(controller.categories.first.children.map((area) => area.areaId), ['g1', 'g2']);
      expect(controller.categories.last.children.map((area) => area.areaId), ['m1']);
      expect(site.requests, 1);
    });
  }
}
