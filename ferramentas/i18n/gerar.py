import json,re,glob
import os; S=os.path.dirname(os.path.abspath(__file__))+'/'
R=os.path.abspath(S+'../..')+'/'
D=json.load(open(S+'dic.json'))
extra=json.load(open(S+'extra.json')) if __import__('os').path.exists(S+'extra.json') else {}
D.update(extra)
import re as _r
D={_r.sub(r'\s+',' ',k).strip():v for k,v in D.items()}
# i18n.js: pequeno, em todas as páginas (escolha do idioma); i18n-en.js: dicionário + tradutor, só em inglês
open(R+'i18n.js','w',encoding='utf-8',newline='\n').write(open(S+'motor.js').read())
m=open(S+'motor-en.js').read().replace('__DICIONARIO__', json.dumps(D,ensure_ascii=False,indent=0,sort_keys=True))
open(R+'i18n-en.js','w',encoding='utf-8',newline='\n').write(m)
print('dic',len(D))
