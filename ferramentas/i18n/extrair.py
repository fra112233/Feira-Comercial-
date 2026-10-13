import re, json, glob, os, html
from html.parser import HTMLParser
import os as _o; R=_o.path.abspath(_o.path.dirname(_o.path.abspath(__file__))+'/../..')+'/'
SKIP={'i18n.js','admin.html','recibo.html','sw.js'}
ACC=re.compile(r'[áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ]')
def bom(s):
    s=re.sub(r'\s+',' ',s).strip()
    if len(s)<2 or not re.search(r'[A-Za-zÀ-ú]{2}',s): return None
    if re.search(r'[{};]|=>|\b(px|rgba|var\(|function|return|const|https?:|\.html|\.js|\.png|\.svg)\b',s): return None
    if re.fullmatch(r'[\w\-.#:\[\]=*>,()\'"/ ]+',s) and ' ' not in s and not s[:1].isupper() and not ACC.search(s): return None
    if re.fullmatch(r'[a-z_]+(\.[a-z_]+)*',s): return None
    if re.fullmatch(r'[a-z][a-zA-Z]+',s): return None   # camelCase / palavras-código
    if s.startswith(('#','.','fa-','fas ','far ','fab ')): return None
    return s
out={}
def add(s,f):
    s=bom(html.unescape(s))
    if s: out.setdefault(s,set()).add(os.path.basename(f))
def strings_js(code,f):
    for m in re.finditer(r'`((?:\\.|[^`\\])*)`|\'((?:\\.|[^\'\\\n])*)\'|"((?:\\.|[^"\\\n])*)"',code):
        s=m.group(1) or m.group(2) or m.group(3) or ''
        s=re.sub(r'\$\{[^}]*\}','\x00',s)
        for parte in re.split(r'<[^>]*>|<[^>]*$|^[^<]*>|\x00|\\n',s):
            add(parte.replace("\\'","'").replace('\\"','"'),f)
        for a in re.finditer(r'(?:placeholder|title|aria-label|alt)=\\?["\']([^"\'\\]+)',s): add(a.group(1),f)
class P(HTMLParser):
    def __init__(s,f): super().__init__(); s.f=f; s.em=None; s.buf=''
    def handle_starttag(s,t,a):
        if t in('script','style'): s.em=t; s.buf=''
        for k,v in a:
            if k in('placeholder','title','aria-label','alt') and v: add(v,s.f)
            if k=='value' and dict(a).get('type') in('button','submit') and v: add(v,s.f)
    def handle_endtag(s,t):
        if t==s.em:
            if t=='script': strings_js(s.buf,s.f)
            s.em=None
    def handle_data(s,d):
        if s.em: s.buf+=d
        else: add(d,s.f)
for f in glob.glob(R+'*.html'):
    if os.path.basename(f) in SKIP: continue
    P(f).feed(open(f,encoding='utf-8').read())
for f in glob.glob(R+'*.js'):
    if os.path.basename(f) in SKIP: continue
    strings_js(open(f,encoding='utf-8').read(),f)
json.dump({k:sorted(v) for k,v in sorted(out.items())},open('textos.json','w'),ensure_ascii=False,indent=0)
print(len(out), sum(len(k) for k in out))
