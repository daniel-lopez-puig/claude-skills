"""Minimal Google Drive v3 client that reuses an rclone Google Drive remote's OAuth token.

No extra credentials: `rclone config` once (type: drive, scope: drive) and this module borrows
the token from ~/.config/rclone/rclone.conf, refreshing it through rclone when it is about to expire.

    from gapi import api, remote_name
    api('GET', 'https://www.googleapis.com/drive/v3/about?fields=user')

The remote is chosen by (first match): GDRIVE_REMOTE env var, the `--remote` handled by the caller
(sets GDRIVE_REMOTE), the default profile's drive.remote in the meeting-recorder config, or the
first drive remote in rclone.conf.
"""
import json, configparser, urllib.request, urllib.error, time, subprocess, datetime, os, sys

CONF = os.path.expanduser('~/.config/rclone/rclone.conf')


def _cfg():
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(CONF)
    return cp


def remote_name():
    r = os.environ.get('GDRIVE_REMOTE')
    if r:
        return r
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        r = subprocess.run([sys.executable, os.path.join(here, 'mrconfig'), 'profile', '-', 'drive.remote'],
                           capture_output=True, text=True).stdout.strip()
        if r and r != 'null':
            return r
    except Exception:
        pass
    cp = _cfg()
    for s in cp.sections():
        if cp[s].get('type') == 'drive':
            return s
    raise SystemExit('no rclone Google Drive remote found; run `rclone config` (type drive, scope drive)')


def _tok(remote):
    cp = _cfg()
    if remote not in cp:
        raise SystemExit(f'rclone remote "{remote}" not found in {CONF}')
    return json.loads(cp[remote]['token'])


REMOTE = remote_name()
_tok_cache = _tok(REMOTE)
_exp = datetime.datetime.fromisoformat(_tok_cache['expiry'])
if _exp < datetime.datetime.now(_exp.tzinfo) + datetime.timedelta(minutes=5):
    subprocess.run(['rclone', 'lsd', REMOTE + ':', '-q'], capture_output=True)   # rclone refreshes the token
    _tok_cache = _tok(REMOTE)
AT = _tok_cache['access_token']


def api(method, url, body=None, raw=False, data=None, ctype='application/json'):
    for attempt in range(7):
        payload = data if data is not None else (json.dumps(body).encode() if body is not None else None)
        req = urllib.request.Request(url, data=payload, method=method,
                                     headers={'Authorization': 'Bearer ' + AT, 'Content-Type': ctype})
        try:
            b = urllib.request.urlopen(req).read()
            return b if raw else (json.loads(b) if b else {})
        except urllib.error.HTTPError as e:
            msg = e.read().decode()
            if e.code in (403, 429, 500, 503) and ('ateLimit' in msg or 'Quota' in msg or e.code >= 500):
                time.sleep(6 * (attempt + 1)); continue
            raise RuntimeError(f'{method} {url.split("?")[0]} -> {e.code}: {msg[:250]}')
    raise RuntimeError('rate limited too long: ' + url)
