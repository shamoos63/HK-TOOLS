import 'wa_parser.dart';

/// Renders a [WaArchive] to a readable, self-contained file.
abstract final class WaExport {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _dateOnly(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _bubble(WaMessage m) {
    if (m.text != null && m.text!.trim().isNotEmpty) return m.text!;
    final label = switch (m.kind) {
      WaMediaKind.image => '📷 Photo',
      WaMediaKind.video => '🎬 Video',
      WaMediaKind.voice => '🎙️ Voice message',
      WaMediaKind.audio => '🎵 Audio',
      WaMediaKind.document => '📄 Document',
      WaMediaKind.sticker => '🩹 Sticker',
      WaMediaKind.gif => 'GIF',
      WaMediaKind.contact => '👤 Contact',
      WaMediaKind.location => '📍 Location',
      WaMediaKind.none => '',
    };
    final name = m.mediaName == null ? '' : ' — ${m.mediaName}';
    return '$label$name'.trim();
  }

  /// One searchable HTML page: a sidebar of chats and, for each, its messages
  /// grouped by day as WhatsApp-style bubbles.
  static String toHtml(WaArchive archive, {String title = 'WhatsApp archive'}) {
    final b = StringBuffer();
    b.writeln('<!doctype html><html lang="en"><head><meta charset="utf-8">');
    b.writeln(
      '<meta name="viewport" content="width=device-width,initial-scale=1">',
    );
    b.writeln('<title>${_esc(title)}</title><style>');
    b.writeln('''
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;background:#0b141a;color:#e9edef;display:flex;height:100vh;overflow:hidden}
#list{width:300px;min-width:240px;border-right:1px solid #222d34;overflow-y:auto;background:#111b21}
#list h1{font-size:15px;margin:0;padding:16px;position:sticky;top:0;background:#202c33;border-bottom:1px solid #222d34}
#search{width:100%;padding:9px 12px;border:none;background:#202c33;color:#e9edef;font-size:13px;border-bottom:1px solid #222d34;position:sticky;top:48px}
.chat{padding:11px 16px;border-bottom:1px solid #1b262c;cursor:pointer}
.chat:hover,.chat.active{background:#2a3942}
.chat .n{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.chat .m{color:#8696a0;font-size:12px}
#pane{flex:1;display:flex;flex-direction:column;overflow:hidden}
#head{padding:14px 18px;background:#202c33;border-bottom:1px solid #222d34;font-weight:600}
#msgs{flex:1;overflow-y:auto;padding:18px;background:#0b141a}
.day{text-align:center;margin:14px 0;color:#8696a0;font-size:12px}
.day span{background:#182229;padding:4px 10px;border-radius:7px}
.row{display:flex;margin:3px 0}
.row.me{justify-content:flex-end}
.bub{max-width:70%;padding:7px 10px;border-radius:8px;background:#202c33;white-space:pre-wrap;word-wrap:break-word}
.row.me .bub{background:#005c4b}
.snd{color:#53bdeb;font-size:12px;font-weight:600;margin-bottom:2px}
.t{color:#8696a0;font-size:11px;float:right;margin:4px 0 -4px 10px}
#empty{margin:auto;color:#8696a0}
''');
    b.writeln('</style></head><body>');
    b.writeln('<div id="list"><h1>${_esc(title)}</h1>');
    b.writeln('<input id="search" placeholder="Search chats">');
    for (var i = 0; i < archive.chats.length; i++) {
      final c = archive.chats[i];
      b.writeln(
        '<div class="chat" data-i="$i" data-name="${_esc(c.name.toLowerCase())}" '
        'onclick="show($i)"><div class="n">${_esc(c.name)}</div>'
        '<div class="m">${c.messageCount} messages'
        '${c.lastTimestampMs == null ? '' : ' · ${_dateOnly(c.lastTimestampMs!)}'}</div></div>',
      );
    }
    b.writeln('</div><div id="pane"><div id="head">Select a chat</div>');
    b.writeln(
      '<div id="msgs"><div id="empty">Pick a chat on the left.</div></div></div>',
    );

    // Message data as JSON, rendered client-side so the page stays small.
    b.writeln('<script>const C=[');
    for (final c in archive.chats) {
      final msgs = archive.messagesFor(c.jid);
      b.write('{n:${_json(c.name)},g:${c.isGroup},m:[');
      for (final m in msgs) {
        b.write(
          '{f:${m.fromMe ? 1 : 0},t:${m.timestampMs},'
          's:${m.sender == null ? 'null' : _json(_shortSender(m.sender!))},'
          'x:${_json(_bubble(m))}},',
        );
      }
      b.write(']},');
    }
    b.writeln('];');
    b.writeln(r'''
function esc(s){return (s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
function dt(ms){const d=new Date(ms),p=n=>String(n).padStart(2,'0');return p(d.getHours())+':'+p(d.getMinutes())}
function day(ms){const d=new Date(ms),p=n=>String(n).padStart(2,'0');return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())}
let cur=-1;
function show(i){cur=i;const c=C[i];document.querySelectorAll('.chat').forEach(e=>e.classList.toggle('active',+e.dataset.i===i));
document.getElementById('head').textContent=c.n;
let h='',last='';
for(const m of c.m){const dk=day(m.t);if(dk!==last){h+='<div class="day"><span>'+dk+'</span></div>';last=dk;}
h+='<div class="row '+(m.f?'me':'you')+'"><div class="bub">'+(c.g&&!m.f&&m.s?'<div class="snd">'+esc(m.s)+'</div>':'')+'<span class="t">'+dt(m.t)+'</span>'+esc(m.x)+'</div></div>';}
document.getElementById('msgs').innerHTML=h||'<div id="empty">No messages.</div>';
document.getElementById('msgs').scrollTop=0;}
document.getElementById('search').addEventListener('input',e=>{const q=e.target.value.toLowerCase();
document.querySelectorAll('.chat').forEach(el=>{el.style.display=el.dataset.name.includes(q)?'':'none';});});
''');
    b.writeln('</script></body></html>');
    return b.toString();
  }

  static String _shortSender(String jid) => '+${jid.split('@').first}';

  static String _json(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', '')}"';

  /// Spreadsheet-friendly CSV (UTF-8 with BOM), one row per message.
  static String toCsv(WaArchive archive) {
    final names = {for (final c in archive.chats) c.jid: c.name};
    String cell(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final rows = <String>[
      [
        'Chat',
        'JID',
        'Date',
        'Direction',
        'Sender',
        'Type',
        'Message',
        'Media file',
      ].map(cell).join(','),
      for (final m in archive.messages)
        [
          names[m.chatJid] ?? m.chatJid,
          m.chatJid,
          _time(m.timestampMs),
          m.fromMe ? 'Sent' : 'Received',
          m.fromMe ? 'Me' : (m.sender == null ? '' : _shortSender(m.sender!)),
          m.kind.name,
          m.text ?? '',
          m.mediaName ?? '',
        ].map(cell).join(','),
    ];
    return '﻿${rows.join('\r\n')}\r\n';
  }
}
