import 'package:flutter/material.dart';

import 'api/generated/dto.dart';

abstract final class PawdayDesign {
  static const paper = Color(0xfff7f4ed);
  static const white = Color(0xfffffefa);
  static const ink = Color(0xff26342d);
  static const muted = Color(0xff778078);
  static const line = Color(0xffe8e5dc);
  static const green = Color(0xff466a50);
  static const greenDark = Color(0xff35543e);
  static const lime = Color(0xffdce8cb);
  static const orange = Color(0xffd7784f);
  static const ease = Cubic(.25, .1, .25, 1);
  static String image(String name) => 'assets/reference/$name.jpg';

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(seedColor: green).copyWith(
      primary: green,
      onPrimary: Colors.white,
      secondary: orange,
      surface: white,
      onSurface: ink,
      outline: line,
      primaryContainer: lime,
      onPrimaryContainer: greenDark,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: const BorderSide(color: line),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'PawdaySans',
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: green),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? green.withValues(alpha: .45)
                : states.contains(WidgetState.hovered)
                ? greenDark
                : green,
          ),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'PawdaySans',
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: green,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: white,
        selectedColor: lime,
        side: const BorderSide(color: line),
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: lime,
        height: 74,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerTheme: const DividerThemeData(color: line),
    );
  }
}

/// CSS-equivalent hover feedback. Disabled controls keep their original behavior.
class ReferenceHover extends StatefulWidget {
  final Widget child;
  final Widget Function(bool hovered)? builder;
  final double lift;
  final int milliseconds;
  final bool enabled;
  const ReferenceHover({
    super.key,
    required this.child,
    this.builder,
    this.lift = 2,
    this.milliseconds = 200,
    this.enabled = true,
  });
  @override
  State<ReferenceHover> createState() => _ReferenceHoverState();
}

class _ReferenceHoverState extends State<ReferenceHover> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduce ? 0 : widget.milliseconds),
        curve: PawdayDesign.ease,
        transform: Matrix4.translationValues(
          0,
          !reduce && widget.enabled && hovered ? -widget.lift : 0,
          0,
        ),
        child:
            widget.builder?.call(!reduce && widget.enabled && hovered) ??
            widget.child,
      ),
    );
  }
}

class PawdayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const PawdayButton({super.key, required this.onPressed, required this.child});
  @override
  Widget build(BuildContext context) => ReferenceHover(
    enabled: onPressed != null,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        boxShadow: onPressed == null
            ? const []
            : [
                BoxShadow(
                  color: PawdayDesign.green.withValues(alpha: .18),
                  offset: const Offset(0, 8),
                  blurRadius: 18,
                ),
              ],
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: MediaQuery.sizeOf(context).width <= 620
              ? const EdgeInsets.symmetric(horizontal: 17, vertical: 13)
              : const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          textStyle: TextStyle(
            fontFamily: 'PawdaySans',
            fontSize: MediaQuery.sizeOf(context).width <= 620 ? 11 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onPressed,
        child: child,
      ),
    ),
  );
}

class ReferenceLoginFrame extends StatelessWidget {
  final Widget child;
  const ReferenceLoginFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth > 800;
      final photo = Image.asset(
        PawdayDesign.image('hero-dogs'),
        fit: BoxFit.cover,
        width: double.infinity,
        height: wide ? 650 : 155,
        semanticLabel: '一起散步的狗狗',
      );
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1184),
          child: Padding(
            padding: EdgeInsets.all(wide ? 28 : 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Material(
                color: PawdayDesign.white,
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: photo),
                          Expanded(child: child),
                        ],
                      )
                    : Column(
                        children: [
                          if (MediaQuery.viewInsetsOf(context).bottom == 0)
                            photo,
                          Expanded(child: child),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ReferenceTextLink extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const ReferenceTextLink({
    super.key,
    required this.label,
    required this.onPressed,
  });
  @override
  State<ReferenceTextLink> createState() => _ReferenceTextLinkState();
}

class _ReferenceTextLinkState extends State<ReferenceTextLink> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: TextButton(
        onPressed: widget.onPressed,
        style: TextButton.styleFrom(overlayColor: Colors.transparent),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 7),
            AnimatedSlide(
              offset: !reduce && hovered
                  ? const Offset(4 / 14, 0)
                  : Offset.zero,
              duration: Duration(milliseconds: reduce ? 0 : 200),
              curve: PawdayDesign.ease,
              child: const Icon(Icons.arrow_forward, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class PawdayBrand extends StatelessWidget {
  const PawdayBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Transform.rotate(
        angle: -.087,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: PawdayDesign.green,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.pets, color: Colors.white, size: 23),
        ),
      ),
      const SizedBox(width: 10),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '爪日',
            style: TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: PawdayDesign.ink,
            ),
          ),
          Text(
            'PAWDAY · PET GOODS',
            style: TextStyle(
              fontSize: 8,
              height: 1.8,
              letterSpacing: 1.2,
              color: PawdayDesign.muted,
            ),
          ),
        ],
      ),
    ],
  );
}

class ReferencePhoto extends StatefulWidget {
  final String image;
  final bool? active;
  final double scale;
  final int milliseconds;
  const ReferencePhoto({
    super.key,
    required this.image,
    this.active,
    this.scale = 1.05,
    this.milliseconds = 450,
  });
  @override
  State<ReferencePhoto> createState() => _ReferencePhotoState();
}

class _ReferencePhotoState extends State<ReferencePhoto> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: ClipRect(
      child: AnimatedScale(
        scale:
            !MediaQuery.disableAnimationsOf(context) &&
                (widget.active ?? hovered)
            ? widget.scale
            : 1,
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context)
              ? 0
              : widget.milliseconds,
        ),
        curve: PawdayDesign.ease,
        child: Image.asset(
          PawdayDesign.image(widget.image),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

class ReferencePlus extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  const ReferencePlus({
    super.key,
    required this.onPressed,
    required this.label,
  });
  @override
  State<ReferencePlus> createState() => _ReferencePlusState();
}

class _ReferencePlusState extends State<ReferencePlus> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedRotation(
        turns: !reduce && hovered ? .25 : 0,
        duration: Duration(milliseconds: reduce ? 0 : 200),
        curve: PawdayDesign.ease,
        child: IconButton(
          onPressed: widget.onPressed,
          tooltip: widget.label,
          icon: const Icon(Icons.add, size: 17),
          style: IconButton.styleFrom(
            backgroundColor: hovered ? PawdayDesign.green : PawdayDesign.lime,
            foregroundColor: hovered ? Colors.white : PawdayDesign.green,
            minimumSize: Size.square(
              MediaQuery.sizeOf(context).width <= 620 ? 28 : 31,
            ),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

class ReferenceProductCard extends StatelessWidget {
  final ConsumerProduct item;
  final VoidCallback onOpen;
  final Widget? selection;
  final int imageIndex;
  const ReferenceProductCard({
    super.key,
    required this.item,
    required this.onOpen,
    this.selection,
    this.imageIndex = 0,
  });
  @override
  Widget build(BuildContext context) {
    final prices = item.offers.map((offer) => offer.sale_price_fen);
    final price = prices.isEmpty
        ? null
        : prices.reduce((a, b) => a < b ? a : b);
    final photo = [
      'product-cat',
      'product-dog',
      'product-treat',
      'product-bowl',
    ][imageIndex % 4];
    return ReferenceHover(
      lift: 5,
      milliseconds: 240,
      child: const SizedBox.shrink(),
      builder: (hovered) => Container(
        decoration: BoxDecoration(
          color: PawdayDesign.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffefede7)),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: PawdayDesign.ink.withValues(alpha: .1),
                    offset: const Offset(0, 16),
                    blurRadius: 35,
                  ),
                ]
              : const [],
        ),
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: '查看${item.name}',
                child: GestureDetector(
                  onTap: onOpen,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ReferencePhoto(image: photo, active: hovered),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: PawdayDesign.white,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              '氛围配图 · 非商品实拍',
                              style: TextStyle(
                                fontSize: 9,
                                color: PawdayDesign.green,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 12, 9, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.brand,
                    style: const TextStyle(
                      fontSize: 10,
                      color: PawdayDesign.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onOpen,
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.pilot_material?.label ?? item.sku_code,
                    style: const TextStyle(
                      fontSize: 10,
                      color: PawdayDesign.muted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          price == null
                              ? '暂无在售报价'
                              : '¥${(price / 100).toStringAsFixed(2)} 起',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ?selection,
                      ReferencePlus(
                        onPressed: onOpen,
                        label: '查看${item.name}的报价',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
