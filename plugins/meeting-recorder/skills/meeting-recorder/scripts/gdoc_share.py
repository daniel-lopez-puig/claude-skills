#!/usr/bin/env python3
"""Share a Google Doc read-only with people, with a notification email. Second step of the
meeting-recorder skill: run ONLY after the owner has reviewed the doc and explicitly said to share it.

    gdoc_share.py <doc_id> --to a@x.com b@y.com [--lang ca|es|en] [--message "..."] [--remote R] [--dry-run]
    gdoc_share.py <doc_id> --list

--list shows who already has access (so a doc is never re-shared silently).
--dry-run prints what would be done and touches nothing.
--lang picks the default notification message from the default profile's share_message in the
config (falls back to a built-in English line); --message overrides it.
Owner and people who already have access are skipped. Prints JSON per address.
"""
import sys, os, json, argparse, subprocess

ap = argparse.ArgumentParser()
ap.add_argument('doc_id')
ap.add_argument('--to', nargs='*', default=[])
ap.add_argument('--message', default=None)
ap.add_argument('--lang', default='en')
ap.add_argument('--remote', default=None)
ap.add_argument('--profile', default='-', help='config profile whose share_message to use')
ap.add_argument('--list', action='store_true')
ap.add_argument('--dry-run', action='store_true')
a = ap.parse_args()
if a.remote:
    os.environ['GDRIVE_REMOTE'] = a.remote
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gapi import api  # noqa: E402

D = 'https://www.googleapis.com/drive/v3/files/'
FALLBACK_MSG = 'Sharing the summary of our meeting. Any correction or nuance, let me know. Thanks.'


def default_message(lang, profile):
    try:
        v = subprocess.run([sys.executable, os.path.join(HERE, 'mrconfig'), 'profile', profile, f'share_message.{lang}'],
                           capture_output=True, text=True).stdout.strip()
        return v or FALLBACK_MSG
    except Exception:
        return FALLBACK_MSG


def perms(doc_id):
    r = api('GET', D + doc_id + '/permissions?fields=permissions(id,type,role,emailAddress)')
    return r.get('permissions', [])


if __name__ == '__main__':
    if a.message is None:
        a.message = default_message(a.lang, a.profile)
    meta = api('GET', D + a.doc_id + '?fields=id,name,webViewLink')
    have = perms(a.doc_id)
    if a.list or not a.to:
        print(json.dumps({'doc': meta['name'], 'link': meta.get('webViewLink'),
                          'access': [{'email': p.get('emailAddress'), 'role': p['role'], 'type': p['type']} for p in have]},
                         ensure_ascii=False, indent=1))
        sys.exit(0)
    already = {p.get('emailAddress', '').lower() for p in have if p.get('emailAddress')}
    for addr in a.to:
        e = addr.strip().lower()
        if not e or '@' not in e:
            print(json.dumps({'email': addr, 'status': 'skipped', 'why': 'not an email'})); continue
        if e in already:
            print(json.dumps({'email': e, 'status': 'skipped', 'why': 'already has access'})); continue
        if a.dry_run:
            print(json.dumps({'email': e, 'status': 'would share', 'role': 'reader', 'notify': True, 'message': a.message}, ensure_ascii=False)); continue
        r = api('POST', D + a.doc_id + '/permissions?sendNotificationEmail=true&fields=id,role',
                {'type': 'user', 'role': 'reader', 'emailAddress': e, 'emailMessage': a.message})
        print(json.dumps({'email': e, 'status': 'shared', 'role': r['role'], 'permission_id': r['id']}))
    print(json.dumps({'doc': meta['name'], 'link': meta.get('webViewLink')}, ensure_ascii=False))
