#!/usr/bin/env python3
"""Create a Google Doc from a Markdown file, in a Drive folder, using an rclone Drive remote's token.

    gdoc_create.py --title "Meeting 2026-09-22 Ana – Acme – Intro" --folder "Company/Meetings" \
                   --md summary.md [--description "..."] [--remote gdrive-x] [--create-folders]

Prints JSON: {"id", "name", "link", "folder"}. The doc is PRIVATE to the token's owner (no sharing
here; see gdoc_share.py). --description is stored in the Drive file description (visible in Drive's
"Details" pane, never in the document body): that is where the calendar-event reference goes.
--remote picks the rclone remote (default: the default profile's drive.remote from the config).
Markdown supported: # / ## / ### headings, - bullets, 1. numbered, **bold**, *italic*, paragraphs.
A leading YAML front-matter block (--- ... ---) is stripped.
"""
import sys, os, json, argparse, html, re, uuid, urllib.parse

ap = argparse.ArgumentParser()
ap.add_argument('--title', required=True)
ap.add_argument('--folder', required=True, help='Drive path, e.g. Company/Meetings')
ap.add_argument('--md', required=True, help='Markdown file, or - for stdin')
ap.add_argument('--description', default='')
ap.add_argument('--remote', default=None, help='rclone Google Drive remote name')
ap.add_argument('--create-folders', action='store_true')
a = ap.parse_args()
if a.remote:
    os.environ['GDRIVE_REMOTE'] = a.remote
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gapi import api  # noqa: E402  (needs GDRIVE_REMOTE set first)

D = 'https://www.googleapis.com/drive/v3/files'
FOLDER = 'application/vnd.google-apps.folder'
GDOC = 'application/vnd.google-apps.document'


def find_child(name, parent, mime=None):
    q = f"name = '{name.replace(chr(39), chr(92)+chr(39))}' and '{parent}' in parents and trashed = false"
    if mime:
        q += f" and mimeType = '{mime}'"
    r = api('GET', D + '?q=' + urllib.parse.quote(q) + '&fields=files(id,name,mimeType)')
    return r.get('files', [])


def resolve_folder(path, create):
    parent = 'root'
    for part in [p for p in path.strip('/').split('/') if p]:
        hits = find_child(part, parent, FOLDER)
        if hits:
            parent = hits[0]['id']
        elif create:
            parent = api('POST', D + '?fields=id', {'name': part, 'mimeType': FOLDER, 'parents': [parent]})['id']
        else:
            raise SystemExit(f'folder not found: {path} (stopped at "{part}"); pass --create-folders to create it')
    return parent


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)
    t = re.sub(r'(?<!\*)\*(?!\*)(.+?)\*', r'<i>\1</i>', t)
    return t


def md_to_html(md):
    out, list_tag, para = [], None, []

    def flush_para():
        if para:
            out.append('<p>' + inline(' '.join(para)) + '</p>')
            para.clear()

    def close_list():
        nonlocal list_tag
        if list_tag:
            out.append(f'</{list_tag}>')
            list_tag = None

    for raw in md.splitlines():
        line = raw.rstrip()
        m = re.match(r'^(#{1,3})\s+(.*)', line)
        if m:
            flush_para(); close_list()
            out.append(f'<h{len(m.group(1))}>{inline(m.group(2))}</h{len(m.group(1))}>')
            continue
        m = re.match(r'^\s*[-*]\s+(.*)', line)
        if m:
            flush_para()
            if list_tag != 'ul':
                close_list(); out.append('<ul>'); list_tag = 'ul'
            out.append(f'<li>{inline(m.group(1))}</li>')
            continue
        m = re.match(r'^\s*\d+[.)]\s+(.*)', line)
        if m:
            flush_para()
            if list_tag != 'ol':
                close_list(); out.append('<ol>'); list_tag = 'ol'
            out.append(f'<li>{inline(m.group(1))}</li>')
            continue
        if not line.strip():
            flush_para(); close_list()
            continue
        close_list()
        para.append(line.strip())
    flush_para(); close_list()
    return '<html><head><meta charset="utf-8"></head><body>' + '\n'.join(out) + '</body></html>'


def create_doc(title, folder_id, html_body, description):
    meta = {'name': title, 'mimeType': GDOC, 'parents': [folder_id]}
    if description:
        meta['description'] = description
    boundary = 'b' + uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{json.dumps(meta)}\r\n'
            f'--{boundary}\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n{html_body}\r\n--{boundary}--').encode('utf-8')
    return api('POST', 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink',
               data=body, ctype=f'multipart/related; boundary={boundary}')


if __name__ == '__main__':
    md = sys.stdin.read() if a.md == '-' else open(a.md, encoding='utf-8').read()
    md = re.sub(r'\A---\n.*?\n---\n', '', md, count=1, flags=re.S)
    folder_id = resolve_folder(a.folder, a.create_folders)
    r = create_doc(a.title, folder_id, md_to_html(md), a.description)
    print(json.dumps({'id': r['id'], 'name': r['name'], 'link': r.get('webViewLink'), 'folder': a.folder}, ensure_ascii=False))
