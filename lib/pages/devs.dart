import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:preconnect/pages/api_test.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

class DevsPage extends StatefulWidget {
  const DevsPage({super.key});

  @override
  State<DevsPage> createState() => _DevsPageState();
}

class _DevsPageState extends State<DevsPage> {
  late Future<String> _subtitleFuture;
  int _secretTapCount = 0;

  @override
  void initState() {
    super.initState();
    _subtitleFuture = _buildVersionSubtitle();
  }

  Future<String> _buildVersionSubtitle() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty && build.isEmpty) return 'App Version';
      if (build.isEmpty) return 'v$version';
      return 'v$version ($build)';
    } catch (_) {
      return 'App Version';
    }
  }

  Future<void> _onHeaderSecretTap() async {
    _secretTapCount += 1;
    if (_secretTapCount < 10) return;
    _secretTapCount = 0;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ApiTestPage()));
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return FutureBuilder<String>(
      future: _subtitleFuture,
      builder: (context, snapshot) {
        final subtitle = snapshot.data ?? 'App Version';
        return BracuPageScaffold(
          title: 'Devs & Support',
          subtitle: subtitle,
          icon: Icons.developer_mode_outlined,
          onHeaderTap: _onHeaderSecretTap,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PreConnect App Runs by Students',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 10),
                    Text(
                      'Community driven and free for every student.',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bug reports, feature requests, and ideas are welcome. '
                      'Please create issues in our GitHub repo.',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _openRepo(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: BracuPalette.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: BracuPalette.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: BracuPalette.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'View Repository',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: BracuPalette.primary,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                              color: BracuPalette.primary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Core Team'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
                children: const [
                  _DevGridTile(
                    name: 'NaiveInvestigator',
                    role: 'Lead Developer',
                    avatarUrl: 'https://github.com/NaiveInvestigator.png',
                    githubUrl: 'https://github.com/NaiveInvestigator',
                    facebookUrl: '',
                  ),
                  _DevGridTile(
                    name: 'Sabbir Bin Abbas',
                    role: 'Developer & UI/UX',
                    avatarUrl: 'https://github.com/sabbirba.png',
                    githubUrl: 'https://github.com/sabbirba',
                    facebookUrl: 'https://facebook.com/Sabbirba10',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Funding & Support'),
              const SizedBox(height: 10),
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'iOS Funding',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'App Store publishing needs the \$99/year Apple Developer '
                      'membership. Any contribution towards this funding will be highly appreciated.',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 12),
                    const BracuFundingSupportContent(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DevGridTile extends StatelessWidget {
  const _DevGridTile({
    required this.name,
    required this.role,
    required this.avatarUrl,
    required this.githubUrl,
    required this.facebookUrl,
  });

  final String name;
  final String role;
  final String avatarUrl;
  final String githubUrl;
  final String facebookUrl;

  Future<void> _openUrl(BuildContext context, String rawUrl) async {
    await openExternalUrl(context, rawUrl);
  }

  Widget _avatarPlaceholder(BuildContext context) {
    final initial = name.trim().isNotEmpty
        ? name.trim().substring(0, 1).toUpperCase()
        : '?';
    return Container(
      color: BracuPalette.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => _openUrl(context, githubUrl),
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ClipOval(
                child: CachedImage(
                  url: avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: _avatarPlaceholder(context),
                  error: _avatarPlaceholder(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            role,
            style: TextStyle(color: textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              _LinkChip(
                label: 'GitHub',
                onTap: () => _openUrl(context, githubUrl),
              ),
              if (facebookUrl.isNotEmpty)
                _LinkChip(
                  label: 'Facebook',
                  onTap: () => _openUrl(context, facebookUrl),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: BracuPalette.primary,
          ),
        ),
      ),
    );
  }
}

Future<void> _openRepo(BuildContext context) async {
  await openExternalUrl(context, 'https://github.com/sabbirba/preconnect');
}
