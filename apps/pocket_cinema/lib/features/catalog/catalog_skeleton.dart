import 'package:flutter/material.dart';

double catalogHeroMetadataHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).width < 600 ? 84 : 64) *
    MediaQuery.textScalerOf(context).scale(11) /
    11;

double catalogHeroTitleHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context)
        .scale(MediaQuery.sizeOf(context).width < 600 ? 26 : 34) *
    1.2 *
    2;

double catalogHeroOverviewHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context)
        .scale(Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) *
    1.6 *
    2;

/// Static placeholders keep the first catalog layout still while it loads.
class CatalogHeroSkeleton extends StatelessWidget {
  const CatalogHeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final maxCoverSize = (MediaQuery.sizeOf(context).height * .36)
                .clamp(160.0, 340.0);
            final coverSize = (width * (width < 600 ? .44 : .59)).clamp(
              160.0,
              maxCoverSize,
            );
            return SizedBox(
              key: const Key('catalog-skeleton-carousel'),
              height: coverSize + 60,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final offset in [-1, 1])
                    Positioned(
                      left:
                          (width - coverSize * .8) / 2 +
                          offset * coverSize * .6,
                      top: 18 + coverSize * .1,
                      width: coverSize * .8,
                      height: coverSize * .8,
                      child: const _SkeletonBlock(dim: true, radius: 8),
                    ),
                  Positioned(
                    left: (width - coverSize * 1.03) / 2,
                    top: 18 - coverSize * .015,
                    width: coverSize * 1.03,
                    height: coverSize * 1.03,
                    child: const _SkeletonBlock(radius: 8),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              SizedBox(
                height: catalogHeroMetadataHeight(context),
                child: const Center(
                  child: _SkeletonBlock(width: 180, height: 24, radius: 20),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: catalogHeroTitleHeight(context),
                child: const Center(
                  child: _SkeletonBlock(width: 220, height: 28),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: catalogHeroOverviewHeight(context),
                child: const Center(
                  child: _SkeletonBlock(width: 280, height: 14, dim: true),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox.fromSize(
                    size: catalogHeroActionSize(context),
                    child: const _SkeletonBlock(radius: 30),
                  ),
                  SizedBox.fromSize(
                    size: catalogHeroActionSize(context, details: true),
                    child: const _SkeletonBlock(radius: 30),
                  ),
                  const _SkeletonBlock(
                    width: 48,
                    height: 48,
                    radius: 24,
                    dim: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Size catalogHeroActionSize(BuildContext context, {bool details = false}) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return Size((details ? 210 : 180) * scale, 60 * scale);
}

class CatalogShelfSkeleton extends StatelessWidget {
  const CatalogShelfSkeleton({this.listView = false, super.key});

  final bool listView;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading titles',
    container: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 32, bottom: 16),
            child: SizedBox(
              height: 32,
              child: Center(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _SkeletonBlock(width: 160, height: 22),
                ),
              ),
            ),
          ),
          if (listView)
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: _SkeletonBlock(height: 80, radius: 12),
              )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 500
                    ? 2
                    : constraints.maxWidth < 850
                    ? 3
                    : constraints.maxWidth < 1100
                    ? 4
                    : 5;
                return GridView.count(
                  key: const Key('catalog-skeleton-grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: .60,
                  children: [
                    for (var i = 0; i < columns; i++) const _SkeletonPoster(),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );
}

class _SkeletonPoster extends StatelessWidget {
  const _SkeletonPoster();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF181B24),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _SkeletonBlock(radius: 12)),
        Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBlock(height: 16),
              SizedBox(height: 6),
              _SkeletonBlock(width: 72, height: 12, dim: true),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width,
    this.height,
    this.radius = 5,
    this.dim = false,
  });

  final double? width, height;
  final double radius;
  final bool dim;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: dim ? const Color(0xFF20242F) : const Color(0xFF2A303E),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
