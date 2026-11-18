import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_units.dart';
import '../services/native_ad_cache.dart';

class NativeAdSlot extends StatefulWidget {
  const NativeAdSlot(
      {super.key, required this.placement, required this.active});
  final NativePlacement placement;
  final bool active;
  @override
  State<NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends State<NativeAdSlot> {
  NativeAdCache? _cache;
  bool _ownsCache = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = NativeAdScope.maybeOf(context);
    if (_cache == null || (shared != null && shared != _cache)) {
      _detach();
      _ownsCache = shared == null;
      _cache = shared ??
          NativeAdCache(
              enabled: true,
              brightness: Theme.of(context).brightness,
              placements: [widget.placement]);
      _cache!.addListener(_changed);
    }
    if (_ownsCache) {
      _cache!
          .configure(enabled: true, brightness: Theme.of(context).brightness);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant NativeAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement) {
      _cache?.release(oldWidget.placement, this);
      if (_ownsCache) {
        _detach();
        _ownsCache = true;
        _cache = NativeAdCache(
            enabled: true,
            brightness: Theme.of(context).brightness,
            placements: [widget.placement]);
        _cache!.addListener(_changed);
      }
    }
  }

  void _detach() {
    _cache?.removeListener(_changed);
    _cache?.release(widget.placement, this);
    if (_ownsCache) _cache?.dispose();
    _cache = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _cache?.adFor(widget.placement);
    if (ad == null ||
        !widget.active ||
        !_cache!.claim(widget.placement, this)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: widget.placement.usesMediaLayout ? 8 : 0),
      child: SizedBox(
          height: widget.placement.usesMediaLayout ? 240 : 54,
          width: double.infinity,
          child: AdWidget(key: ObjectKey(ad), ad: ad)),
    );
  }
}
