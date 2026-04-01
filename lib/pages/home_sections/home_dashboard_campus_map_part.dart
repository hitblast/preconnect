part of 'package:preconnect/pages/home.dart';

extension _HomeDashboardCampusMapPart on _HomeDashboardState {
  Future<void> _handlePhoneTap(BuildContext context, String rawPhone) async {
    final normalized = _normalizePhoneValue(rawPhone);
    if (normalized.isEmpty) return;
    copyToClipboard(context, normalized);
    await openPhoneDialer(context, normalized);
  }

  Future<_CampusMapData?> _fetchCampusMapData({
    bool forceRefresh = false,
  }) async {
    final payload = await ScraperDataService().fetchMap(
      path: '/data/map',
      cacheKey: 'scraper_campus_map_v1',
      ttl: const Duration(hours: 12),
      forceRefresh: forceRefresh,
    );
    if (payload == null) return null;
    final parsed = _CampusMapData.fromJson(payload);
    final hasAnyImage =
        parsed.mapImageUrl.isNotEmpty || parsed.images.isNotEmpty;
    if (hasAnyImage || forceRefresh) return parsed;

    final freshPayload = await ScraperDataService().fetchMap(
      path: '/data/map',
      cacheKey: 'scraper_campus_map_v1',
      ttl: const Duration(hours: 12),
      forceRefresh: true,
    );
    if (freshPayload == null) return parsed;
    return _CampusMapData.fromJson(freshPayload);
  }

  Future<String?> _fetchTransportScheduleUrl({
    bool forceRefresh = false,
  }) async {
    final rows = await ScraperDataService().fetchList(
      path: '/data/transport',
      cacheKey: 'scraper_transport_v1',
      ttl: const Duration(hours: 12),
      forceRefresh: forceRefresh,
    );
    for (final row in rows) {
      final url = '${row['schedule_url'] ?? ''}'.trim();
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  Future<void> _openCampusMapBottomSheet() async {
    _campusMapFuture ??= _fetchCampusMapData();
    _transportScheduleUrlFuture ??= _fetchTransportScheduleUrl();
    var highlightsExpanded = false;
    var officesExpanded = false;
    var emergencyExpanded = false;
    if (!mounted) return;
    await showBracuBottomSheet<void>(
      context,
      title: 'Campus Map',
      subtitle: 'Directions, highlights and contacts',
      builder: (sheetContext, textPrimary, textSecondary) {
        return FutureBuilder<List<dynamic>>(
          future: Future.wait<dynamic>([
            _campusMapFuture!,
            _transportScheduleUrlFuture!,
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: BracuLoading());
            }
            final values = snapshot.data;
            final mapData = values != null && values.isNotEmpty
                ? values[0] as _CampusMapData?
                : null;
            final transportScheduleUrl = values != null && values.length > 1
                ? (values[1] as String?)
                : null;
            if (mapData == null) {
              final sheetScroll = bracuBottomSheetScrollController(context);
              return ListView(
                controller: sheetScroll,
                children: [
                  Text(
                    'Campus map data is unavailable right now.',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }
            final sheetScroll = bracuBottomSheetScrollController(context);

            Widget sectionTitle(String value) => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                value,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            );

            Widget minimalBlock({required Widget child}) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BracuPalette.card(sheetContext).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: textSecondary.withValues(alpha: 0.16),
                  ),
                ),
                child: child,
              );
            }

            Widget actionButton({
              required IconData icon,
              required String label,
              required VoidCallback? onPressed,
            }) {
              return OutlinedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BracuPalette.primary,
                  side: BorderSide(
                    color: BracuPalette.primary.withValues(alpha: 0.52),
                    width: 1.1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            return ListView(
              controller: sheetScroll,
              children: [
                minimalBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mapData.mapImageUrl.isNotEmpty) ...[
                        BracuImageCarousel(
                          imageUrls: <String>[mapData.mapImageUrl],
                          borderRadius: 10,
                          aspectRatio: 16 / 10,
                          imageFit: BoxFit.fitWidth,
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        mapData.campusName.isEmpty
                            ? 'BRAC University Campus'
                            : mapData.campusName,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (mapData.address.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          mapData.address,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final buttonWidth = (constraints.maxWidth - gap) / 2;
                    final resolvedTransportUrl =
                        transportScheduleUrl != null &&
                            transportScheduleUrl.trim().isNotEmpty
                        ? transportScheduleUrl.trim()
                        : mapData.transportScheduleUrl;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.directions_rounded,
                            label: 'Open Map',
                            onPressed: mapData.googleMapsUrl.isEmpty
                                ? null
                                : () => openExternalUrl(
                                    sheetContext,
                                    mapData.googleMapsUrl,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.open_in_new_rounded,
                            label: 'Campus Life',
                            onPressed: mapData.sourceUrl.isEmpty
                                ? null
                                : () => openExternalUrl(
                                    sheetContext,
                                    mapData.sourceUrl,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.alternate_email_rounded,
                            label: 'Email',
                            onPressed: mapData.primaryEmail.isEmpty
                                ? null
                                : () => openMailComposer(
                                    sheetContext,
                                    mapData.primaryEmail,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: actionButton(
                            icon: Icons.directions_bus_rounded,
                            label: 'Transport',
                            onPressed: resolvedTransportUrl.isEmpty
                                ? null
                                : () => openExternalUrl(
                                    sheetContext,
                                    resolvedTransportUrl,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth,
                          child: actionButton(
                            icon: Icons.call_outlined,
                            label: mapData.primaryPhoneRaw.isEmpty
                                ? 'Call'
                                : mapData.primaryPhoneRaw,
                            onPressed: mapData.primaryPhone.isEmpty
                                ? null
                                : () => _handlePhoneTap(
                                    sheetContext,
                                    mapData.primaryPhoneRaw.isEmpty
                                        ? mapData.primaryPhone
                                        : mapData.primaryPhoneRaw,
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (mapData.images.isNotEmpty) ...[
                  sectionTitle('Campus Gallery'),
                  BracuImageCarousel(
                    imageUrls: mapData.images,
                    borderRadius: 12,
                  ),
                ],
                if (mapData.highlights.isNotEmpty) ...[
                  sectionTitle('Highlights'),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      final visibleHighlights = highlightsExpanded
                          ? mapData.highlights
                          : mapData.highlights.take(3).toList(growable: false);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...visibleHighlights.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Icon(
                                      Icons.circle,
                                      size: 6,
                                      color: BracuPalette.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (mapData.highlights.length > 3)
                            buildCenteredOutlinedActionButton(
                              label: highlightsExpanded
                                  ? 'Show Less'
                                  : 'Show More',
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              onPressed: () {
                                setLocalState(() {
                                  highlightsExpanded = !highlightsExpanded;
                                });
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (mapData.offices.isNotEmpty) ...[
                  sectionTitle('General Contacts'),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      final visibleOffices = officesExpanded
                          ? mapData.offices
                          : mapData.offices.take(3).toList(growable: false);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...visibleOffices.map((office) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: minimalBlock(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      office.office,
                                      style: TextStyle(
                                        color: textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (office.emails.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      ...office.emails.map(
                                        (email) => Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                email,
                                                style: TextStyle(
                                                  color: textSecondary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => openMailComposer(
                                                sheetContext,
                                                email,
                                              ),
                                              icon: const Icon(
                                                Icons.email_outlined,
                                                size: 18,
                                              ),
                                              tooltip: 'Email',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'No email listed',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (mapData.offices.length > 3)
                            buildCenteredOutlinedActionButton(
                              label: officesExpanded
                                  ? 'Show Less'
                                  : 'Show More',
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              onPressed: () {
                                setLocalState(() {
                                  officesExpanded = !officesExpanded;
                                });
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (mapData.emergencyContacts.isNotEmpty) ...[
                  sectionTitle('Emergency Contacts'),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      final visibleEmergency = emergencyExpanded
                          ? mapData.emergencyContacts
                          : mapData.emergencyContacts
                                .take(3)
                                .toList(growable: false);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...visibleEmergency.map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: minimalBlock(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        color: textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (item.services.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.services,
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    if (item.phones.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      ...item.phones.map(
                                        (phone) => Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                phone,
                                                style: TextStyle(
                                                  color: textSecondary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => _handlePhoneTap(
                                                sheetContext,
                                                phone,
                                              ),
                                              icon: const Icon(
                                                Icons.call_outlined,
                                                size: 18,
                                              ),
                                              tooltip: 'Call',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'No phone listed',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (mapData.emergencyContacts.length > 3)
                            buildCenteredOutlinedActionButton(
                              label: emergencyExpanded
                                  ? 'Show Less'
                                  : 'Show More',
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              onPressed: () {
                                setLocalState(() {
                                  emergencyExpanded = !emergencyExpanded;
                                });
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
