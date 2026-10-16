import 'package:flutter/material.dart';

/// What the last action did and what the tester should see on screen.
class DemoStatus {
  final String action;
  final String expectation;
  const DemoStatus(this.action, this.expectation);
}

class DemoAction {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const DemoAction(this.label, this.color, this.onTap);
}

class DemoActionSection {
  final String label;
  final List<DemoAction> actions;
  const DemoActionSection(this.label, this.actions);
}

/// Shared layout for every demo page: viewer on top, then a status panel
/// (chips, last action, expectation), then a scrollable row of actions.
class DemoScaffold extends StatelessWidget {
  final String title;
  final String howTo;
  final Widget viewer;
  final DemoStatus status;
  final List<(String, String)> chips;
  final List<DemoActionSection> sections;
  final List<Widget> appBarActions;

  const DemoScaffold({
    super.key,
    required this.title,
    required this.howTo,
    required this.viewer,
    required this.status,
    this.chips = const [],
    this.sections = const [],
    this.appBarActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...appBarActions,
          IconButton(
            tooltip: 'What to try',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHowTo(context),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: viewer),
            _StatusPanel(chips: chips, status: status),
            if (sections.isNotEmpty) _ActionBar(sections: sections),
          ],
        ),
      ),
    );
  }

  void _showHowTo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(howTo)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final List<(String, String)> chips;
  final DemoStatus status;

  const _StatusPanel({required this.chips, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chips.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, value) in chips) _Chip(label, value),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            'Action: ${status.action}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Expect: ${status.expectation}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  const _Chip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final List<DemoActionSection> sections;
  const _ActionBar({required this.sections});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SizedBox(
        height: 96,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (final section in sections) ...[
                _Section(section),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final DemoActionSection section;
  const _Section(this.section);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            section.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Row(
          children: [
            for (final action in section.actions) ...[
              _ActionButton(action),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final DemoAction action;
  const _ActionButton(this.action);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: action.color,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          action.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
