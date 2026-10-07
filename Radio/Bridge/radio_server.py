#!/usr/bin/env python3
"""Internet Radio catalogue and durable per-device state for Apple TV 3."""
import json, os, threading, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
PORT=int(os.environ.get('ATV3_RADIO_PORT','8100'))
BASE='https://de1.api.radio-browser.info'
STATE=os.path.join(os.path.dirname(__file__),'radio_state.json')
UA='RetroReel3-InternetRadio/0.2'
lock=threading.RLock()
try:
    with open(STATE,encoding='utf-8') as f: state=json.load(f)
except (OSError,ValueError): state={}
def save():
    tmp=STATE+'.tmp'
    with open(tmp,'w',encoding='utf-8') as f: json.dump(state,f,ensure_ascii=False,indent=2)
    os.replace(tmp,STATE)
def get(path):
    req=urllib.request.Request(BASE+path,headers={'User-Agent':UA})
    with urllib.request.urlopen(req,timeout=12) as r: return json.load(r)
def slim(x):
    return {k:x.get(k) for k in ('stationuuid','name','url_resolved','favicon','country','countrycode','language','tags','codec','bitrate','hls','votes','lastcheckok')}
def catalog(kind,query):
    p={'hidebroken':'true','order':'votes','reverse':'true','limit':str(min(200,max(1,int(query.get('limit',['60'])[0]))))}
    if kind=='stations':
        for k in ('countrycode','tag','name','language'):
            v=query.get(k,[''])[0].strip()
            if v:p[k]=v
        return {'stations':[slim(x) for x in get('/json/stations/search?'+urllib.parse.urlencode(p)) if x.get('lastcheckok')]}
    if kind=='countries':return {'countries':get('/json/countries?hidebroken=true&order=stationcount&reverse=true')}
    if kind=='tags':return {'tags':get('/json/tags?hidebroken=true&order=stationcount&reverse=true&limit=150')}
    raise ValueError('unknown catalogue')
class Handler(BaseHTTPRequestHandler):
    def sendj(self,obj,code=200):
        b=json.dumps(obj,ensure_ascii=False).encode('utf-8'); self.send_response(code)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin','*')
        self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def do_GET(self):
        u=urllib.parse.urlparse(self.path);q=urllib.parse.parse_qs(u.query)
        try:
            if u.path=='/health':return self.sendj({'ok':True,'service':'ATV3Bridge Internet Radio','version':'0.2'})
            if u.path.startswith('/v1/radio/'):
                action=u.path.split('/')[-1]
                if action in ('stations','countries','tags'):
                    return self.sendj({'ok':True,**catalog(action,q)})
                if action in ('favorites','recent','state'):
                    device=q.get('device',['default'])[0][:64]
                    with lock:
                        data=state.get(device,{'favorites':[],'recent':[]})
                        return self.sendj({'ok':True,**data} if action=='state' else {'ok':True,action:data.get(action,[])})
            return self.sendj({'ok':False,'error':'not found'},404)
        except Exception as e:return self.sendj({'ok':False,'error':str(e)},502)
    def do_POST(self):
        u=urllib.parse.urlparse(self.path)
        try:
            n=int(self.headers.get('Content-Length','0'))
            if n<1 or n>16384:return self.sendj({'ok':False,'error':'invalid length'},400)
            payload=json.loads(self.rfile.read(n).decode('utf-8'))
            if not isinstance(payload,dict):raise ValueError('object required')
            device=str(payload.get('device','default'))[:64]
            item=payload.get('station')
            action=u.path.rsplit('/',1)[-1]
            if u.path not in ('/v1/radio/favorite','/v1/radio/played') or not isinstance(item,dict):return self.sendj({'ok':False,'error':'invalid request'},400)
            uuid=str(item.get('stationuuid',''))
            if not uuid or len(uuid)>128:return self.sendj({'ok':False,'error':'stationuuid required'},400)
            item=slim(item)
            with lock:
                s=state.setdefault(device,{'favorites':[],'recent':[]})
                key='favorites' if action=='favorite' else 'recent'
                a=[x for x in s[key] if x.get('stationuuid')!=uuid]
                if action=='favorite' and any(x.get('stationuuid')==uuid for x in s[key]):pass
                else:a.insert(0,item)
                s[key]=a[:200 if key=='favorites' else 50];save()
                return self.sendj({'ok':True,'favorite':any(x.get('stationuuid')==uuid for x in s['favorites'])})
        except Exception as e:return self.sendj({'ok':False,'error':str(e)},400)
    def log_message(self,*a):pass
if __name__=='__main__':ThreadingHTTPServer(('0.0.0.0',PORT),Handler).serve_forever()
