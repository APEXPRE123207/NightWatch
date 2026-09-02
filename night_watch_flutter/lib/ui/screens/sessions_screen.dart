import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_watch_flutter/models/event_model.dart';
import 'package:night_watch_flutter/models/session.dart';
import 'package:night_watch_flutter/services/monitoring_controller.dart';
import 'package:night_watch_flutter/ui/screens/event_detail_screen.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';
import 'package:night_watch_flutter/ui/widgets/event_card.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final MonitoringController _controller = MonitoringController();
  List<NightSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final list = await _controller.getAllSessions();
    if (mounted) {
      setState(() {
        _sessions = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Night History'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: NightWatchTheme.accentSpeech),
            )
          : _sessions.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  color: NightWatchTheme.accentSpeech,
                  backgroundColor: NightWatchTheme.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      return _SessionCard(
                        session: session,
                        onDelete: () async {
                          await _controller.deleteSession(session.id!);
                          _loadSessions();
                        },
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bedtime_outlined, size: 64, color: NightWatchTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No Recorded Nights Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: NightWatchTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a monitoring session tonight to record sound anomalies.',
            style: TextStyle(fontSize: 13, color: NightWatchTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  final NightSession session;
  final VoidCallback onDelete;

  const _SessionCard({required this.session, required this.onDelete});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _isExpanded = false;
  List<RecordedEvent> _events = [];
  bool _isLoadingEvents = false;

  Future<void> _toggleExpand() async {
    final next = !_isExpanded;
    if (next && _events.isEmpty) {
      setState(() => _isLoadingEvents = true);
      final events = await MonitoringController().getEventsForSession(widget.session.id!);
      if (mounted) {
        setState(() {
          _events = events;
          _isLoadingEvents = false;
          _isExpanded = next;
        });
      }
    } else {
      setState(() => _isExpanded = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEE, MMM d, yyyy').format(widget.session.startTime);
    final timeRange =
        '${DateFormat('hh:mm a').format(widget.session.startTime)} - ${widget.session.endTime != null ? DateFormat('hh:mm a').format(widget.session.endTime!) : 'In progress'}';

    final durationHours = widget.session.durationSeconds ~/ 3600;
    final durationMins = (widget.session.durationSeconds % 3600) ~/ 60;
    final durStr = durationHours > 0 ? '${durationHours}h ${durationMins}m' : '${durationMins}m';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            title: Text(
              dateStr,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: NightWatchTheme.textPrimary,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$timeRange  •  $durStr',
                style: const TextStyle(fontSize: 12, color: NightWatchTheme.textSecondary),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.session.eventCount > 0
                        ? NightWatchTheme.accentSpeech.withValues(alpha: 0.15)
                        : NightWatchTheme.surfaceBorder,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.session.eventCount} events',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.session.eventCount > 0
                          ? NightWatchTheme.accentSpeech
                          : NightWatchTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: NightWatchTheme.textSecondary,
                  ),
                  onPressed: _toggleExpand,
                ),
              ],
            ),
            onTap: _toggleExpand,
          ),

          // Expandable Event List
          if (_isExpanded) ...[
            const Divider(color: NightWatchTheme.surfaceBorder, height: 1),
            if (_isLoadingEvents)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: NightWatchTheme.accentSpeech),
              )
            else if (_events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'No anomaly events recorded during this session.',
                  style: TextStyle(color: NightWatchTheme.textMuted, fontSize: 13),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: _events.map((e) {
                    return EventCard(
                      event: e,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EventDetailScreen(event: e),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
