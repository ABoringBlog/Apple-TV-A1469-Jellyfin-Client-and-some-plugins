#!/usr/bin/env python3
"""CloudTune bridge for Apple TV 3.

The bridge stores the user's own provider session locally, talks to an external
NeteaseCloudMusicApi-compatible service, and exposes a small LAN API for the
legacy ATV3 client. It does not bypass provider authorization: unavailable or
unauthorized playback URLs are returned as unavailable.
"""
import json,os,urllib.parse,urllib.request,urllib.error,time,threading,secrets,base64,hashlib
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
PORT=int(os.environ.get('CLOUDTUNE_PORT','8101'))
UPSTREAM=os.environ.get('CLOUDTUNE_UPSTREAM','http://127.0.0.1:18300').rstrip('/')
SESSION_DIR=Path(os.environ.get('CLOUDTUNE_SESSION_DIR',str(Path.home()/'.config'/'cloudtune-atv3'))).expanduser()
SESSION_FILE=SESSION_DIR/'session.json'
AUTH_LOCK=threading.Lock()
QR_SESSIONS={}

def save_session(cookie):
    if not isinstance(cookie,str) or 'MUSIC_U=' not in cookie: return False
    SESSION_DIR.mkdir(mode=0o700,parents=True,exist_ok=True)
    os.chmod(SESSION_DIR,0o700)
    tmp=SESSION_DIR/('session.'+secrets.token_hex(6)+'.tmp')
    with open(tmp,'x') as f:
        os.chmod(tmp,0o600)
        json.dump({'cookie':cookie,'saved_at':int(time.time())},f)
    os.replace(tmp,SESSION_FILE)
    return True

def api(path,params):
    url=UPSTREAM+path+'?'+urllib.parse.urlencode(params)
    with urllib.request.urlopen(url,timeout=12) as r:return json.load(r)
def account_api(path,params=None):
    if not SESSION_FILE.exists():raise PermissionError('login_required')
    saved=json.loads(SESSION_FILE.read_text())
    cookie=saved.get('cookie','')
    if not cookie or 'MUSIC_U=' not in cookie:raise PermissionError('login_required')
    query=dict(params or {})
    query['cookie']=cookie
    return api(path,query)

# Session-scoped, persistent metadata cache. No session cookies in cached files.
CACHE_BASE=SESSION_DIR/'library-cache'
CACHE_LOCK=threading.RLock()
CACHE_BUSY=set()
def cache_path(kind,ident=''):
    if not SESSION_FILE.exists():raise PermissionError('login_required')
    cookie=json.loads(SESSION_FILE.read_text()).get('cookie','')
    if 'MUSIC_U=' not in cookie:raise PermissionError('login_required')
    scope=hashlib.sha256(cookie.encode()).hexdigest()[:20]
    return CACHE_BASE/scope/(kind+('-'+ident if ident else '')+'.json')
def cache_read(kind,ident=''):
    try:
        with CACHE_LOCK:return json.loads(cache_path(kind,ident).read_text())
    except (OSError,ValueError,PermissionError):return None
def cache_write(kind,ident,data):
    path=cache_path(kind,ident);path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    tmp=path.with_name(path.name+'.'+secrets.token_hex(4)+'.tmp')
    with open(tmp,'x') as file:json.dump(data,file,ensure_ascii=False)
    os.chmod(tmp,0o600);os.replace(tmp,path)
def fetch_library(kind,ident=''):
    if kind=='playlists':
        status=account_api('/login/status');account=(status.get('data') or {}).get('account') or {}
        if not account.get('id'):raise PermissionError('session_invalid')
        all_items=[];offset=0
        while True:
            result=account_api('/user/playlist',{'uid':str(account['id']),'limit':100,'offset':offset})
            if result.get('code')!=200:raise ValueError('playlists_unavailable')
            batch=result.get('playlist') or []
            for row in batch:
                if isinstance(row,dict):all_items.append({'id':str(row.get('id','')),'name':row.get('name',''),'track_count':row.get('trackCount',0),'cover_url':row.get('coverImgUrl',''),'creator':(row.get('creator') or {}).get('nickname','')})
            offset+=len(batch)
            if not batch or len(batch)<100:break
        return {'ok':True,'playlists':all_items,'cached_at':int(time.time())}
    if kind=='tracks':
        all_tracks=[];offset=0
        while True:
            result=account_api('/playlist/track/all',{'id':ident,'limit':100,'offset':offset})
            if result.get('code')!=200:raise ValueError('tracks_unavailable')
            batch=result.get('songs') or []
            for item in batch:
                if not isinstance(item,dict):continue
                artists=item.get('ar') or [];cover=(item.get('al') or {}).get('picUrl','')
                all_tracks.append({'id':str(item.get('id','')),'name':item.get('name',''),'artists':[x.get('name','') for x in artists if isinstance(x,dict)],'album':(item.get('al') or {}).get('name',''),'duration_ms':item.get('dt',0),'cover_url':'/v1/music/cover?url='+urllib.parse.quote(cover,safe='') if cover else ''})
            offset+=100
            if not batch or offset>=10000:break
        # Preserve original playlist order and unavailable entries.
        try:
            original=account_api('/playlist/detail',{'id':ident})
            ids=[str(row.get('id')) for row in ((original.get('playlist') or {}).get('trackIds') or []) if row.get('id')]
            if ids:
                by_id={row['id']:row for row in all_tracks}
                all_tracks=[by_id.get(sid,{'id':sid,'name':'歌曲信息不可用','artists':[],'album':'','duration_ms':0,'cover_url':'','unavailable':True}) for sid in ids]
        except Exception as exc:print('playlist detail order unavailable',type(exc).__name__,flush=True)
        return {'ok':True,'playlist_id':ident,'tracks':all_tracks,'count':len(all_tracks),'cached_at':int(time.time())}
    raise ValueError('invalid_kind')
def refresh_cache(kind,ident='',force=False):
    key=kind+':'+ident
    with CACHE_LOCK:
        if key in CACHE_BUSY:return
        CACHE_BUSY.add(key)
    def work():
        try:
            result=fetch_library(kind,ident)
            cache_write(kind,ident,result)
            if kind=='playlists':
                for pl in result['playlists']:
                    playlist_id=pl.get('id','')
                    if playlist_id.isdigit():refresh_cache('tracks',playlist_id)
        except Exception as exc:
            print('cache refresh failed',kind,ident,type(exc).__name__,flush=True)
        finally:
            with CACHE_LOCK:CACHE_BUSY.discard(key)
    threading.Thread(target=work,daemon=True,name='library-cache-'+kind).start()
def warm_library():
    try:
        for pl in (cache_read('playlists') or {}).get('playlists',[]):
            ident=pl.get('id','')
            if ident.isdigit() and cache_read('tracks',ident) is None:refresh_cache('tracks',ident)
        refresh_cache('playlists')
    except Exception:pass

PLAY_URL_LOCK=threading.RLock()
PLAY_URL_CACHE={}
PLAY_URL_BUSY=set()
def playback_url(song_id,level='exhigh'):
    key=(hashlib.sha256(SESSION_FILE.read_bytes()).hexdigest() if SESSION_FILE.exists() else '',song_id,level)
    now=time.time()
    with PLAY_URL_LOCK:
        cached=PLAY_URL_CACHE.get(key)
        if cached and cached['expiry']>now+30:return dict(cached['reply'],cache_hit=True)
    result=account_api('/song/url/v1',{'id':song_id,'level':level})
    entries=result.get('data') or []
    item=entries[0] if entries and isinstance(entries[0],dict) else {}
    url=item.get('url')
    if not isinstance(url,str) or not url.startswith(('https://','http://')):
        return {'ok':False,'error':'playback_unavailable_or_not_authorized','provider_code':item.get('code')}
    reply={'ok':True,'id':song_id,'url_resolved':url,'format':item.get('type'),'bitrate':item.get('br'),'quality':level}
    # Provider URL lifetime is bounded by its expiry field, if supplied.
    expiry_ms=item.get('expi',0)
    try:ttl=min(240,max(0,float(expiry_ms)-60)) if expiry_ms else 120
    except (TypeError,ValueError):ttl=120
    if ttl>=30:
        with PLAY_URL_LOCK:
            PLAY_URL_CACHE[key]={'expiry':time.time()+ttl,'reply':reply}
            if len(PLAY_URL_CACHE)>150:PLAY_URL_CACHE.clear()
    return reply

def queue_prefetch(ids,level='exhigh'):
    for sid in ids[:4]:
        if not isinstance(sid,str) or not sid.isdigit():continue
        key=(sid,level)
        with PLAY_URL_LOCK:
            if key in PLAY_URL_BUSY:continue
            PLAY_URL_BUSY.add(key)
        def worker(song_id=sid,busy_key=key):
            try:playback_url(song_id,level)
            except Exception as exc:print('prefetch error',type(exc).__name__,flush=True)
            finally:
                with PLAY_URL_LOCK:PLAY_URL_BUSY.discard(busy_key)
        threading.Thread(target=worker,daemon=True).start()

HISTORY_LOCK=threading.RLock()
def normalize_song(item):
    album=item.get('al') or item.get('album') or {}
    artists=item.get('ar') or item.get('artists') or []
    cover=album.get('picUrl','') if isinstance(album,dict) else ''
    if isinstance(cover,str) and cover.startswith('http://'):cover='https://'+cover[7:]
    return {'id':str(item.get('id','')),'name':item.get('name') or '未知歌曲',
            'artists':[a.get('name','') for a in artists if isinstance(a,dict)],
            'album':album.get('name','') if isinstance(album,dict) else '',
            'duration_ms':item.get('dt') or item.get('duration') or 0,
            'cover_url':'/v1/music/cover?url='+urllib.parse.quote(cover,safe='') if cover else ''}
def history_tracks():
    return (cache_read('history') or {}).get('tracks',[])
def record_history(ident):
    with HISTORY_LOCK:
        all_known={}
        for playlist in (cache_read('playlists') or {}).get('playlists',[]):
            for song in (cache_read('tracks',playlist.get('id','')) or {}).get('tracks',[]):
                all_known[song.get('id')]=song
        song=all_known.get(ident)
        if not song:return False
        existing=history_tracks()
        rows=[song]+[row for row in existing if row.get('id')!=ident]
        cache_write('history','',{'ok':True,'tracks':rows[:100],'cached_at':int(time.time())})
        return True


MIRROR_SYNC_LOCK=threading.Lock()
MIRROR_RUNNING=False
MIRROR_CHANGED=0
MIRROR_ERRORS=[]
def mirror_sync():
    global MIRROR_RUNNING,MIRROR_CHANGED,MIRROR_ERRORS
    if not MIRROR_SYNC_LOCK.acquire(False):return
    MIRROR_RUNNING=True;MIRROR_CHANGED=0;MIRROR_ERRORS=[]
    try:
        try:
            recommended=account_api('/recommend/songs')
            items=(recommended.get('data') or {}).get('dailySongs') or []
            songs=[normalize_song(t) for t in items if isinstance(t,dict)]
            if songs:cache_write('recommend','',{'ok':True,'tracks':songs,'cached_at':int(time.time())})
        except Exception as ex:MIRROR_ERRORS.append('recommend:'+type(ex).__name__)
        fresh=fetch_library('playlists')
        old=cache_read('playlists') or {'playlists':[]}
        old_ids={p.get('id') for p in old['playlists']}
        new_ids={p.get('id') for p in fresh['playlists']}
        cache_write('playlists','',fresh)
        MIRROR_CHANGED+=len(new_ids.symmetric_difference(old_ids))
        for pl in fresh['playlists']:
            sid=pl.get('id','')
            if not sid.isdigit():continue
            try:
                previous=cache_read('tracks',sid) or {'tracks':[]}
                current=fetch_library('tracks',sid)
                if not current['tracks'] and previous['tracks']:
                    MIRROR_ERRORS.append('empty upstream list '+sid);continue
                old_tracks={t.get('id') for t in previous['tracks']}
                added=[t for t in current['tracks'] if t.get('id') not in old_tracks]
                new_tracks={t.get('id') for t in current['tracks']}
                MIRROR_CHANGED+=len(old_tracks.symmetric_difference(new_tracks))
                cache_write('tracks',sid,current)
                for song in current['tracks']:
                    tid=song.get('id','')
                    if not tid.isdigit():continue
                    try:
                        if not cache_read('lyrics',tid):
                            d=api('/lyric',{'id':tid})
                            cache_write('lyrics',tid,{'ok':True,'id':tid,'lrc':(d.get('lrc') or {}).get('lyric',''),'translated':(d.get('tlyric') or {}).get('lyric',''),'cached_at':int(time.time())})
                        url=urllib.parse.urlsplit(song.get('cover_url',''))
                        cover=urllib.parse.parse_qs(url.query).get('url',[''])[0]
                        if cover:prefetch_cover(cover)
                    except Exception as ex:MIRROR_ERRORS.append(type(ex).__name__)
            except Exception as ex:MIRROR_ERRORS.append('playlist '+sid+':'+type(ex).__name__)
    except Exception as ex:MIRROR_ERRORS.append('sync:'+type(ex).__name__)
    finally:MIRROR_RUNNING=False;MIRROR_SYNC_LOCK.release()

def prefetch_cover(source):
    if source.startswith('http://'):source='https://'+source[7:]
    parsed=urllib.parse.urlsplit(source)
    if parsed.scheme!='https' or not parsed.hostname or not parsed.hostname.endswith('.music.126.net'):return
    key=hashlib.sha256(source.encode()).hexdigest()
    folder=CACHE_BASE/'artwork';folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    file=folder/(key+'.bin')
    mime=folder/(key+'.mime')
    if file.exists() and mime.exists():return
    with urllib.request.urlopen(source,timeout=10) as response:
        content_type=response.headers.get('Content-Type','image/jpeg').split(';')[0].strip()
        data=response.read(1200001)
    if content_type not in ('image/jpeg','image/jpg','image/png','image/webp'):return
    if not 0<len(data)<=1200000:return
    tmp=file.with_name(file.name+'.'+secrets.token_hex(4)+'.tmp');tmp.write_bytes(data);os.replace(tmp,file)
    mime.write_text(content_type)

class Handler(BaseHTTPRequestHandler):
    def respond(self,code,payload):
        body=json.dumps(payload,ensure_ascii=False).encode()
        self.send_response(code);self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def do_GET(self):
        u=urllib.parse.urlsplit(self.path);path=u.path;q=urllib.parse.parse_qs(u.query)
        if path=='/health':return self.respond(200,{'ok':True,'service':'CloudTune Bridge','version':'0.2.0'})
        if path=='/v1/music/mirror/start':
            if not MIRROR_RUNNING:threading.Thread(target=mirror_sync,daemon=True,name='cloudtune-mirror-sync').start()
            return self.respond(200,{'ok':True,'running':MIRROR_RUNNING})
        if path=='/v1/music/mirror/status':
            return self.respond(200,{'ok':True,'running':MIRROR_RUNNING,'changes':MIRROR_CHANGED,'errors':MIRROR_ERRORS[-5:]})
        if path=='/v1/music/capabilities':return self.respond(200,{'ok':True,'metadata_provider':'external-api','features':{'search':True,'song_detail':True,'lyrics':True,'playlists':False,'playback':False,'qr_login':True},'auth':'qr_pending' if not SESSION_FILE.exists() else 'session_saved'})
        try:
            if path=='/v1/music/likes':
                cached=cache_read('liked')
                if cached:return self.respond(200,cached)
                status=account_api('/login/status')
                account=(status.get('data') or {}).get('account') or {}
                uid=account.get('id')
                if not uid:return self.respond(401,{'ok':False,'error':'login_required'})
                response=account_api('/likelist',{'uid':str(uid)})
                ids=[str(x) for x in response.get('ids',[]) if str(x).isdigit()]
                result={'ok':True,'ids':ids,'cached_at':int(time.time())}
                cache_write('liked','',result)
                return self.respond(200,result)
            if path=='/v1/music/likes/set':
                sid=q.get('id',[''])[0]
                value=q.get('like',[''])[0]
                if not sid.isdigit() or value not in ('true','false'):
                    return self.respond(400,{'ok':False,'error':'invalid_like_request'})
                result=account_api('/like',{'id':sid,'like':value})
                if result.get('code')!=200:return self.respond(502,{'ok':False,'code':result.get('code')})
                with CACHE_LOCK:
                    cached=cache_read('liked') or {'ok':True,'ids':[]}
                    ids=set(cached.get('ids',[]))
                    if value=='true':ids.add(sid)
                    else:ids.discard(sid)
                    cache_write('liked','',{'ok':True,'ids':sorted(ids),'cached_at':int(time.time())})
                return self.respond(200,{'ok':True,'liked':value=='true'})
            if path=='/v1/music/recent':
                return self.respond(200,{'ok':True,'tracks':history_tracks()})
            if path=='/v1/music/recent/record':
                ident=q.get('id',[''])[0]
                if not ident.isdigit():return self.respond(400,{'ok':False})
                return self.respond(200,{'ok':record_history(ident)})
            if path=='/v1/music/recommend':
                cached=cache_read('recommend')
                if cached:return self.respond(200,cached)
                result=account_api('/recommend/songs')
                items=(result.get('data') or {}).get('dailySongs') or []
                tracks=[normalize_song(t) for t in items if isinstance(t,dict)]
                payload={'ok':True,'tracks':tracks,'cached_at':int(time.time())}
                if tracks:cache_write('recommend','',payload)
                return self.respond(200,payload)
            if path=='/v1/music/cover':
                source=q.get('url',[''])[0]
                if source.startswith('http://'):
                    source='https://'+source[7:]
                parsed=urllib.parse.urlsplit(source)
                if parsed.scheme!='https' or not parsed.hostname or not parsed.hostname.endswith('.music.126.net') or parsed.username or parsed.password or parsed.port not in (None,443):
                    return self.respond(400,{'ok':False,'error':'invalid_cover_source'})
                image_dir=CACHE_BASE/'artwork'
                key=hashlib.sha256(source.encode()).hexdigest()
                image_path=image_dir/(key+'.bin')
                mime_path=image_dir/(key+'.mime')
                try:
                    raw=image_path.read_bytes();content_type=mime_path.read_text()
                except OSError:
                    request=urllib.request.Request(source,headers={'User-Agent':'Mozilla/5.0'})
                    with urllib.request.urlopen(request,timeout=10) as upstream:
                        content_type=upstream.headers.get('Content-Type','').split(';')[0].strip()
                        if content_type not in ('image/jpeg','image/jpg','image/png','image/webp'):
                            return self.respond(502,{'ok':False,'error':'invalid_cover_type'})
                        raw=upstream.read(1200001)
                    if len(raw)>1200000:return self.respond(502,{'ok':False,'error':'cover_too_large'})
                    image_dir.mkdir(parents=True,exist_ok=True,mode=0o700)
                    temp=image_dir/(key+'.'+secrets.token_hex(4)+'.tmp')
                    temp.write_bytes(raw);os.chmod(temp,0o600);os.replace(temp,image_path)
                    mime_path.write_text(content_type)
                self.send_response(200);self.send_header('Content-Type','image/jpeg' if content_type=='image/jpg' else content_type)
                self.send_header('Cache-Control','public, max-age=86400');self.send_header('Content-Length',str(len(raw)))
                self.end_headers();self.wfile.write(raw);return
            if path=='/v1/music/auth/qr/start':
                with AUTH_LOCK:
                    now=time.monotonic()
                    for token,item in list(QR_SESSIONS.items()):
                        if now-item['created']>300: QR_SESSIONS.pop(token,None)
                    # One active login QR per household ATV. Reuse it to avoid exhausting slots.
                    recent=[(token,item) for token,item in QR_SESSIONS.items() if now-item['created']<240]
                    if recent:
                        token,item=max(recent,key=lambda pair:pair[1]['created'])
                        return self.respond(200,{'ok':True,'token':token,'qrurl':item['qrurl'],'expires_in':int(300-(now-item['created'])),'status':'waiting_scan'})
                    QR_SESSIONS.clear()
                response=api('/login/qr/key',{'timestamp':int(time.time()*1000)})
                key=response.get('data',{}).get('unikey')
                if not isinstance(key,str) or len(key)>128 or not key:return self.respond(502,{'ok':False,'error':'qr_key_failed'})
                created=api('/login/qr/create',{'key':key,'qrimg':'true','timestamp':int(time.time()*1000)})
                qrurl=created.get('data',{}).get('qrurl','')
                if not isinstance(qrurl,str) or not qrurl.startswith('https://music.163.com/'):return self.respond(502,{'ok':False,'error':'qr_create_failed'})
                token=secrets.token_urlsafe(24)
                with AUTH_LOCK: QR_SESSIONS[token]={'key':key,'created':time.monotonic(),'last_poll':0,'qrurl':qrurl,'qrimg':created.get('data',{}).get('qrimg','')}
                return self.respond(200,{'ok':True,'token':token,'qrurl':qrurl,'expires_in':300,'status':'waiting_scan'})
            if path=='/v1/music/auth/qr/image':
                token=q.get('token',[''])[0]
                with AUTH_LOCK: state=QR_SESSIONS.get(token)
                if not state or time.monotonic()-state['created']>300:return self.respond(404,{'ok':False,'error':'invalid_session'})
                data=state['qrimg']
                if not isinstance(data,str) or 'base64,' not in data:return self.respond(502,{'ok':False,'error':'qr_image_unavailable'})
                raw=base64.b64decode(data.split('base64,',1)[1],validate=True)
                if not raw.startswith(b'\x89PNG') or len(raw)>300000:return self.respond(502,{'ok':False,'error':'invalid_qr_image'})
                self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
                return
            if path=='/v1/music/auth/qr/status':
                token=q.get('token',[''])[0]
                with AUTH_LOCK:
                    state=QR_SESSIONS.get(token)
                    if not state:return self.respond(404,{'ok':False,'error':'invalid_session'})
                    now=time.monotonic()
                    if now-state['created']>300:
                        QR_SESSIONS.pop(token,None)
                        return self.respond(200,{'ok':True,'status':'expired'})
                    if now-state['last_poll']<2:return self.respond(429,{'ok':False,'error':'poll_too_fast'})
                    state['last_poll']=now
                    key=state['key']
                result=api('/login/qr/check',{'key':key,'timestamp':int(time.time()*1000)})
                code=result.get('code',0)
                status={800:'expired',801:'waiting_scan',802:'waiting_confirm',803:'authorized'}.get(code,'upstream_error')
                if code==803:
                    if not save_session(result.get('cookie')):
                        return self.respond(502,{'ok':False,'error':'missing_auth_cookie'})
                    with AUTH_LOCK: QR_SESSIONS.pop(token,None)
                if code==800:
                    with AUTH_LOCK: QR_SESSIONS.pop(token,None)
                return self.respond(200,{'ok':True,'status':status})
            if path=='/v1/music/auth/status':
                if not SESSION_FILE.exists():return self.respond(200,{'ok':True,'session_saved':False,'authenticated':False})
                result=account_api('/login/status')
                body=result.get('data',{})
                verified=body.get('code')==200 and isinstance(body.get('account'),dict) and bool(body['account'].get('id'))
                return self.respond(200,{'ok':True,'session_saved':True,'authenticated':verified})
            if path=='/v1/music/account':
                result=account_api('/login/status')
                body=result.get('data',{})
                account=body.get('account') or {}
                profile=body.get('profile') or {}
                if not isinstance(account,dict) or not account.get('id'):
                    return self.respond(401,{'ok':False,'error':'session_invalid'})
                return self.respond(200,{'ok':True,'user_id':str(account['id']),'nickname':profile.get('nickname',''),'avatar_url':profile.get('avatarUrl','')})
            if path.startswith('/v1/music/playlists/') and path.endswith('/tracks'):
                playlist_id=path.split('/')[4]
                if not playlist_id.isdigit():return self.respond(400,{'ok':False,'error':'invalid_playlist_id'})
                cached=cache_read('tracks',playlist_id)
                refresh_cache('tracks',playlist_id) if q.get('refresh',['0'])[0]=='1' or cached is None else None
                return self.respond(200,cached if cached is not None else {'ok':True,'playlist_id':playlist_id,'tracks':[],'loading':True})
            if path=='/v1/music/playlists':
                cached=cache_read('playlists')
                refresh_cache('playlists') if q.get('refresh',['0'])[0]=='1' or cached is None else None
                return self.respond(200,cached if cached is not None else {'ok':True,'playlists':[],'loading':True})
            if path=='/v1/music/search':
                keyword=q.get('q',[''])[0].strip()[:80]
                if not keyword:return self.respond(400,{'ok':False,'error':'missing_query'})
                data=api('/search',{'keywords':keyword,'limit':min(int(q.get('limit',['20'])[0]),40),'type':1})
                tracks=[]
                for s in data.get('result',{}).get('songs',[]):
                    tracks.append({'id':str(s.get('id','')),'name':s.get('name',''),'artists':[a.get('name','') for a in s.get('artists',[])],'album':s.get('album',{}).get('name',''),'duration_ms':s.get('duration',0)})
                return self.respond(200,{'ok':True,'query':keyword,'tracks':tracks})
            if path.startswith('/v1/music/tracks/') and path.endswith('/lyrics'):
                track=path.split('/')[4]
                if not track.isdigit():return self.respond(400,{'ok':False,'error':'invalid_track_id'})
                cached=cache_read('lyrics',track)
                if cached:return self.respond(200,cached)
                data=api('/lyric',{'id':track})
                result={'ok':True,'id':track,'lrc':(data.get('lrc') or {}).get('lyric',''),'translated':(data.get('tlyric') or {}).get('lyric',''),'cached_at':int(time.time())}
                cache_write('lyrics',track,result)
                return self.respond(200,result)
            if path=='/v1/music/playback/prefetch':
                ids=q.get('ids',[''])[0].split(',')[:4]
                queue_prefetch(ids)
                return self.respond(200,{'ok':True,'queued':len([sid for sid in ids if sid.isdigit()])})
            if path.startswith('/v1/music/tracks/') and path.endswith('/playback'):
                song_id=path.split('/')[4]
                if not song_id.isdigit():return self.respond(400,{'ok':False,'error':'invalid_track_id'})
                level=q.get('quality',['exhigh'])[0]
                if level not in ('standard','exhigh','lossless'):return self.respond(400,{'ok':False,'error':'invalid_quality'})
                result=playback_url(song_id,level)
                return self.respond(200 if result.get('ok') else 403,result)
            if path.startswith('/v1/music/'):
                return self.respond(503,{'ok':False,'error':'provider_not_configured'})
        except PermissionError:
            return self.respond(401,{'ok':False,'error':'login_required'})
        except (ValueError,urllib.error.URLError,TimeoutError,KeyError) as exc:
            return self.respond(502,{'ok':False,'error':'upstream_unavailable','detail':type(exc).__name__})
        return self.respond(404,{'ok':False,'error':'not_found'})
    def log_message(self,*args):pass
if __name__=='__main__':
    ThreadingHTTPServer((os.environ.get('CLOUDTUNE_BIND','0.0.0.0'),PORT),Handler).serve_forever()
