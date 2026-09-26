import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/kick/kick_site.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';

/// The remote page size is fixed by Kick, not the user's grid setting.
class KickAreasController extends ServerFixedPageController<LiveArea> {
  KickAreasController(this.site) : super(fixedServerPageSize: 32);
  final KickSite site;
  bool _fetchFailed = false;

  @override
  Future<void> goToPage(int page) async {
    final previous = currentPage;
    _fetchFailed = false;
    await super.goToPage(page);
    if (_fetchFailed && !isClosed) currentPage = previous;
  }

  @override
  Future<void> loadMoreData() async {
    final previous = currentPage;
    _fetchFailed = false;
    await super.loadMoreData();
    if (_fetchFailed && !isClosed) currentPage = previous;
  }

  @override
  Future<List<LiveArea>> fetchFixedNetworkData(int bigPage, int fixedSize) async {
    try {
      final groups = await site.getCategores(bigPage, 32);
      if (isClosed) return [];
      return groups.expand((group) => group.children).toList();
    } catch (_) {
      _fetchFailed = true;
      rethrow;
    }
  }
}

class KickAreasPage extends StatelessWidget {
  const KickAreasPage({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<KickAreasController>(tag: Sites.kickSite);
    return BasePageView<KickAreasController, LiveArea>(
      controller: controller,
      enableRefresh: true,
      enableLoadMore: true,
      customMobileBottomPadding: 85,
      customDesktopBottomPadding: 135,
      showScrollToTopBtn: SettingsService.to.page.showScrollToTopBtn.value,
      showPageSizeSelector: SettingsService.to.page.showPageSizeSelector.value,
      pageSizeOptions: SettingsService.to.page.pageSizeOptions,
      emptyBuilder: (_) =>
          EmptyView(icon: Icons.grid_view, title: i18n('empty_areas_title'), subtitle: i18n('empty_areas_subtitle')),
      contentBuilder: (context, items, scroll) => LayoutBuilder(
        builder: (_, box) {
          final columns = box.maxWidth > 1280
              ? 9
              : box.maxWidth > 960
              ? 7
              : box.maxWidth > 640
              ? 5
              : 3;
          final spacing = SettingsService.to.theme.crossAxisSpacing.value;
          final width = (box.maxWidth - 12 - spacing * (columns - 1)) / columns;
          return GridView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 80),
            addAutomaticKeepAlives: false,
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.value,
              mainAxisExtent: width + 72,
            ),
            itemBuilder: (_, index) => AreaCard(key: ValueKey('kick:${items[index].areaId}'), category: items[index]),
          );
        },
      ),
    );
  }
}
