import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/generated/dto.dart';
import 'catalog_repository.dart';
import 'reference_ui.dart';

String historyMoney(int? value) =>
    value == null ? '未采集 / 未公开' : '¥${(value / 100).toStringAsFixed(2)}';

class PriceHistoryDialog extends ConsumerStatefulWidget {
  final String offerId, merchantName;
  const PriceHistoryDialog({
    super.key,
    required this.offerId,
    required this.merchantName,
  });
  @override
  ConsumerState<PriceHistoryDialog> createState() => _PriceHistoryState();
}

class _PriceHistoryState extends ConsumerState<PriceHistoryDialog> {
  int days = 30, generation = 0;
  bool loading = true;
  OfferPriceHistory? data;
  String? error;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    final g = ++generation;
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final result = await ref
          .read(catalogRepositoryProvider)
          .priceHistory(widget.offerId, days);
      if (mounted && g == generation) setState(() => data = result);
    } catch (_) {
      if (mounted && g == generation) setState(() => error = '价格记录暂时无法加载，请重试。');
    } finally {
      if (mounted && g == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.merchantName} · 价格记录'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30 天')),
                ButtonSegment(value: 90, label: Text('90 天')),
              ],
              selected: {days},
              onSelectionChanged: (value) {
                days = value.first;
                load();
              },
            ),
            const SizedBox(height: 16),
            const Text('同一商家、门店和规格的日末商品报价，按上海日历记录。不含运费、优惠券或结账实付。'),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null) ...[
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(onPressed: load, child: const Text('重试')),
            ],
            if (data case final h?) ...[
              const SizedBox(height: 16),
              Text(
                '已记录 ${h.observed_days} / ${h.days} 天 · ${h.from_date} — ${h.to_date}',
              ),
              if (h.observed_days < 2) const Text('公开价格记录不足，暂不足以形成趋势。未采集或未公开的日期留空。'),
              Text(
                '已记录日末最低 ${historyMoney(h.lowest_recorded_daily_sale_price_fen)} · 最高 ${historyMoney(h.highest_recorded_daily_sale_price_fen)}',
              ),
              const SizedBox(height: 12),
              if (h.observed_days > 0) PriceHistoryChart(points: h.points),
              const SizedBox(height: 8),
              const Text('绿色：普通商品标价 · 橙色：会员标价（需符合会员资格）。缺失或未公开时不连线。仅为报价记录，不代表当时库存或成交。'),
              ExpansionTile(
                title: const Text('查看逐日记录'),
                tilePadding: EdgeInsets.zero,
                children: [
                  for (final p in h.points.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 90, child: Text(p.date)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(historyMoney(p.sale_price_fen)),
                                if (p.member_price_fen != null)
                                  Text(
                                    '会员 ${historyMoney(p.member_price_fen)}',
                                  ),
                                if (p.recorded_at != null)
                                  Text(
                                    '依据 ${p.recorded_at}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

class PriceHistoryChart extends StatelessWidget {
  final List<PriceHistoryPoint> points;
  const PriceHistoryChart({super.key, required this.points});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '报价曲线，详细数值可通过查看逐日记录读取',
    child: SizedBox(
      height: 150,
      width: double.infinity,
      child: CustomPaint(painter: _PricePainter(points)),
    ),
  );
}

class _PricePainter extends CustomPainter {
  final List<PriceHistoryPoint> points;
  _PricePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final values = points
        .expand((p) => [p.sale_price_fen, p.member_price_fen])
        .whereType<int>()
        .toList();
    if (values.isEmpty) return;
    final low = values.reduce(math.min).toDouble(),
        high = values.reduce(math.max).toDouble();
    final range = math.max(high - low, 100.0),
        bottom = low - range * .1,
        top = high + range * .1;
    final grid = Paint()
      ..color = PawdayDesign.line
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        grid,
      );
    }
    for (final member in [false, true]) {
      final paint = Paint()
        ..color = member ? PawdayDesign.orange : PawdayDesign.green
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      bool active = false;
      for (int i = 0; i < points.length; i++) {
        final value = member
            ? points[i].member_price_fen
            : points[i].sale_price_fen;
        if (value == null) {
          active = false;
          continue;
        }
        final position = Offset(
          size.width * i / math.max(points.length - 1, 1),
          size.height * (top - value) / (top - bottom),
        );
        if (active) {
          path.lineTo(position.dx, position.dy);
        } else {
          path.moveTo(position.dx, position.dy);
        }
        canvas.drawCircle(position, 3, Paint()..color = paint.color);
        active = true;
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PricePainter old) => old.points != points;
}
