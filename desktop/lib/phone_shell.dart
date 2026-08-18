// The phone's chrome: a bar of sections along the bottom, a plain title bar on top, and the
// player between them.
//
// This file may re-arrange the FRAME and nothing else. Every section, every detail page and the
// player itself are the same widgets the window and the television show — [_PhoneShell] is handed
// `_content()` and `_searchBar()` already built by [_HomeShellState]. The moment something here
// needs its own version of a section, that is evidence the section is wrong: fix it there, the
// way `_searchBar` grew a narrow branch rather than a phone copy of itself.
//
// A part of main.dart rather than a library of its own. The chrome reads `_HomeShellState`'s
// private state and the same private colours as every other screen; publishing a dozen members
// for one caller would be a larger and riskier change than the chrome itself.
part of 'main.dart';

/// Which icon stands for a section on the bottom bar.
///
/// Public only so a test can assert it answers for every id in [NavSections.items] — an icon that
/// silently falls through to the placeholder is the kind of thing nobody notices in a screenshot.
IconData sectionIcon(int id) => switch (id) {
      5 => Icons.home_rounded,
      0 => Icons.album_rounded,
      4 => Icons.music_note_rounded,
      1 => Icons.person_rounded,
      2 => Icons.search_rounded,
      3 => Icons.explore_rounded,
      6 => Icons.download_rounded,
      _ => Icons.circle_outlined,
    };

/// The frame a phone gets. Everything inside it is handed in already built.
class _PhoneShell extends StatelessWidget {
  const _PhoneShell({
    required this.view,
    required this.searchBar,
    required this.content,
    required this.onSelect,
  });

  final int view;

  /// Null on the sections that have nothing to search — the shell decides, not this file.
  final Widget? searchBar;
  final Widget content;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final badge = context.watch<DownloadManager>().jobs.where((j) => j.busy).length;
    final search = searchBar;
    return Scaffold(
      // The keyboard covers the two bottom bars rather than lifting them.
      //
      // With the default the body shrinks, so the player and the section bar come to rest on top
      // of the keyboard — two bars stacked on a keyboard, over what is left of the album grid.
      // The only text field in this frame is the search box directly under the title bar, and the
      // keyboard never reaches that high.
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          _PhoneTopBar(title: NavSections.labelOf(view)),
          const _OfflineBanner(),
          // No tvOverscan here: a television is 960 points wide and never reaches this frame.
          Expanded(
            child: Column(
              children: [
                if (search != null) search,
                Expanded(child: content),
              ],
            ),
          ),
          // The player and the sections read as one block at the bottom of the screen, so only the
          // lower of the two keeps the gesture inset. Left to themselves both reserve it, and the
          // two reservations stack into an empty strip between them.
          const PlayerBar(bottomSafeArea: false),
          PhoneNavBar(
            active: view,
            badge: badge,
            onSelect: onSelect,
            onMore: () => _openMoreSheet(context, active: view, onSelect: onSelect),
          ),
        ],
      ),
    );
  }
}

/// The section you are in, and the way into the settings.
///
/// No download badge here even though the compact bar this replaces carried one: downloads now
/// have a place of their own on the bottom bar, and it carries the count. Saying it twice on one
/// screen is noise.
class _PhoneTopBar extends StatelessWidget {
  const _PhoneTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // The status bar keeps the panel colour; only the contents move down, so the top of the screen
    // still reads as one piece rather than a black strip above the app.
    final top = MediaQuery.viewPaddingOf(context).top;
    return SizedBox(
      height: 52 + top,
      child: Padding(
        padding: EdgeInsets.only(top: top, left: 18, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded, size: 22),
              tooltip: 'Instellingen',
              // 48, not the 44 the rest of this app uses. 44 is Apple's figure; Android asks for
              // 48dp, and this bar is on an Android phone far more often than on an iPad.
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => openSettings(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sections, along the bottom edge where a thumb can reach them.
///
/// Reads no store of its own — the active section and the badge are handed in. That is what makes
/// it the one piece of the phone frame a widget test can render on its own, without the fourteen
/// providers and the media_kit initialisation that building the real shell would need.
///
/// Hand-built rather than a Material [NavigationBar]: five destinations across a 320-point screen
/// leave 64 points each, and Material's own label does not shorten itself to fit.
class PhoneNavBar extends StatelessWidget {
  const PhoneNavBar({
    super.key,
    required this.active,
    required this.badge,
    required this.onSelect,
    required this.onMore,
  });

  /// The section currently shown. One of [NavSections.items]' ids — not necessarily one of the
  /// four with a place here.
  final int active;

  /// Downloads running. Zero hides the dot.
  final int badge;

  final ValueChanged<int> onSelect;
  final VoidCallback onMore;

  static const _height = 58.0;

  @override
  Widget build(BuildContext context) {
    const ids = NavSections.phonePrimary;
    // Sitting in a section that lives under “Meer” lights “Meer” instead of nothing at all.
    final inMore = !ids.contains(active);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      // The same colour the player bar uses, so the two read as one block rather than two stacked
      // surfaces. A Material rather than a coloured Container: the taps below draw their ripple on
      // the nearest Material, and an opaque box in between paints over it.
      color: const Color(0xFF12141D),
      child: Container(
        height: _height + bottom,
        padding: EdgeInsets.only(bottom: bottom),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
        child: Row(
          children: [
            for (final id in ids)
              _tab(
                icon: sectionIcon(id),
                label: NavSections.shortLabelOf(id),
                selected: id == active,
                badge: id == 6 ? badge : 0,
                onTap: () => onSelect(id),
              ),
            _tab(
              icon: Icons.more_horiz_rounded,
              label: 'Meer',
              selected: inMore,
              badge: 0,
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab({
    required IconData icon,
    required String label,
    required bool selected,
    required int badge,
    required VoidCallback onTap,
  }) {
    final colour = selected ? _accent : _muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        // No Pressable: this bar exists below 600 points and a television is 960 wide, so nothing
        // here is ever reached with a remote.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 23, color: colour),
                if (badge > 0)
                  Positioned(
                    right: -7,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('$badge',
                          style:
                              const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sections that did not fit on the bar, and the settings.
///
/// The list is [NavSections.phoneMore], which is computed from what the bar carries — so a section
/// added to [NavSections.items] turns up here on its own.
Future<void> _openMoreSheet(
  BuildContext context, {
  required int active,
  required ValueChanged<int> onSelect,
}) async {
  final chosen = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: _panel,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, label) in NavSections.phoneMore)
            ListTile(
              leading: Icon(sectionIcon(id), size: 21),
              title: Text(label),
              selected: id == active,
              selectedTileColor: _accent.withValues(alpha: .16),
              selectedColor: Colors.white,
              onTap: () => Navigator.pop(sheet, id),
            ),
          const Divider(color: _line, height: 1),
          ListTile(
            leading: const Icon(Icons.settings_rounded, size: 21),
            title: const Text('Instellingen'),
            onTap: () {
              Navigator.pop(sheet);
              openSettings(context);
            },
          ),
        ],
      ),
    ),
  );
  if (chosen != null) onSelect(chosen);
}
