#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import urlopen, Request
import argparse, datetime, json, os, time

WMO={0:"Clear",1:"Mostly clear",2:"Partly cloudy",3:"Cloudy",45:"Fog",48:"Rime fog",51:"Light drizzle",53:"Drizzle",55:"Heavy drizzle",56:"Freezing drizzle",57:"Heavy freezing drizzle",61:"Light rain",63:"Rain",65:"Heavy rain",66:"Freezing rain",67:"Heavy freezing rain",71:"Light snow",73:"Snow",75:"Heavy snow",77:"Snow grains",80:"Rain showers",81:"Rain showers",82:"Heavy showers",85:"Snow showers",86:"Heavy snow showers",95:"Thunderstorm",96:"Thunderstorm / hail",99:"Severe thunderstorm / hail"}
CACHE_TTL=300
CONFIG_PATH=CACHE_PATH=None
_cache=None; _cache_time=0; _geo_cache=None; _geo_time=0

def load_config():
    cfg={"auto_location":True,"location":"Auto location","latitude":None,"longitude":None,"timezone":"UTC"}
    try:
        with open(CONFIG_PATH,"r",encoding="utf-8") as f:
            loaded=json.load(f)
        if isinstance(loaded,dict): cfg.update(loaded)
    except FileNotFoundError:
        pass
    return cfg

def network_location(cfg):
    global _geo_cache,_geo_time
    if not cfg.get("auto_location",True): return cfg
    now=time.time()
    if _geo_cache and now-_geo_time<21600: return dict(cfg,**_geo_cache)
    try:
        req=Request("https://ipwho.is/",headers={"User-Agent":"ATV3Bridge/1.0"})
        with urlopen(req,timeout=5) as r: g=json.load(r)
        if g.get("success") and g.get("latitude") is not None and g.get("longitude") is not None:
            city=str(g.get("city") or "Auto location"); region=str(g.get("region_code") or g.get("region") or "")
            zone=((g.get("timezone") or {}).get("id") or "UTC")
            _geo_cache={"location":city+((", "+region) if region else ""),"latitude":float(g["latitude"]),"longitude":float(g["longitude"]),"timezone":zone}
            _geo_time=now
            return dict(cfg,**_geo_cache)
    except Exception:
        pass
    return cfg

def load_disk_cache():
    try:
        with open(CACHE_PATH,"r",encoding="utf-8") as f: return json.load(f)
    except Exception: return None

def rows(block,keys,limit):
    times=block.get("time",[]); out=[]
    for i,t in enumerate(times[:limit]):
        item={"time":t}
        for key in keys:
            vals=block.get(key,[]); item[key]=vals[i] if i<len(vals) else None
        if "weather_code" in item: item["condition"]=WMO.get(item["weather_code"],"Weather")
        out.append(item)
    return out

def fetch():
    global _cache,_cache_time
    now=time.time()
    if _cache and now-_cache_time<CACHE_TTL: return _cache
    cfg=network_location(load_config())
    if cfg.get("latitude") is None or cfg.get("longitude") is None:
        raise RuntimeError("No location available. Configure weather_config.json or enable working auto_location.")
    lat=float(cfg["latitude"]); lon=float(cfg["longitude"]); location=str(cfg.get("location") or "Weather"); zone=str(cfg.get("timezone") or "UTC")
    current="temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day"
    hourly="temperature_2m,apparent_temperature,weather_code,precipitation_probability,wind_speed_10m,is_day"
    daily="weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,wind_speed_10m_max"
    url=("https://api.open-meteo.com/v1/forecast"
         f"?latitude={lat}&longitude={lon}&current={current}&hourly={hourly}&daily={daily}"
         f"&timezone={zone.replace('/', '%2F')}&forecast_days=7")
    req=Request(url,headers={"User-Agent":"ATV3Bridge/1.0"})
    with urlopen(req,timeout=8) as r: raw=json.load(r)
    c=raw.get("current",{}); h=raw.get("hourly",{}); dd=raw.get("daily",{})
    payload={"ok":True,"location":location,"latitude":lat,"longitude":lon,
      "condition":WMO.get(c.get("weather_code"),"Weather"),"weather_code":c.get("weather_code"),
      "temperature_c":c.get("temperature_2m"),"feels_like_c":c.get("apparent_temperature"),
      "humidity":c.get("relative_humidity_2m"),"wind_kmh":c.get("wind_speed_10m"),
      "wind_direction":c.get("wind_direction_10m"),"wind_gust_kmh":c.get("wind_gusts_10m"),
      "is_day":c.get("is_day"),"updated":c.get("time") or datetime.datetime.now().astimezone().isoformat(),
      "hourly":rows(h,["temperature_2m","apparent_temperature","weather_code","precipitation_probability","wind_speed_10m","is_day"],24),
      "daily":rows(dd,["weather_code","temperature_2m_max","temperature_2m_min","precipitation_probability_max","sunrise","sunset","wind_speed_10m_max"],7)}
    _cache=payload; _cache_time=now
    try:
        tmp=CACHE_PATH+".tmp"
        with open(tmp,"w",encoding="utf-8") as f: json.dump(payload,f,ensure_ascii=False,separators=(",",":"))
        os.replace(tmp,CACHE_PATH)
    except Exception: pass
    return payload

class H(BaseHTTPRequestHandler):
    def send_json(self,obj,status=200):
        body=json.dumps(obj,ensure_ascii=False,separators=(",",":")).encode("utf-8")
        self.send_response(status); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Cache-Control","no-store"); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path=="/health": self.send_json({"ok":True,"service":"ATV3Bridge Weather"}); return
        if self.path!="/v1/weather": self.send_json({"ok":False,"error":"not found"},404); return
        try: self.send_json(fetch())
        except Exception as e:
            if _cache:
                stale=dict(_cache); stale.update({"stale":True,"error":str(e)}); self.send_json(stale); return
            self.send_json({"ok":False,"error":str(e)},502)
    def log_message(self,fmt,*args): pass

def main():
    global CONFIG_PATH,CACHE_PATH,_cache
    base=os.path.dirname(os.path.abspath(__file__))
    p=argparse.ArgumentParser()
    p.add_argument("--bind",default="0.0.0.0"); p.add_argument("--port",type=int,default=8099)
    p.add_argument("--config",default=os.path.join(base,"weather_config.json")); p.add_argument("--cache",default=os.path.join(base,"weather_cache.json"))
    a=p.parse_args(); CONFIG_PATH=os.path.abspath(a.config); CACHE_PATH=os.path.abspath(a.cache); _cache=load_disk_cache()
    HTTPServer((a.bind,a.port),H).serve_forever()
if __name__=="__main__": main()
