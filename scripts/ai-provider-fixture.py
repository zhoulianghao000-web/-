"""Explicit local HTTP protocol fixture for CI browser/Dart integration. Never live DeepSeek inference."""
import argparse,json
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
parser=argparse.ArgumentParser();parser.add_argument('--test-only',action='store_true',required=True);parser.add_argument('--port',type=int,default=9195);args=parser.parse_args()
class Handler(BaseHTTPRequestHandler):
 def do_POST(self):
  if self.path!='/chat/completions' or self.headers.get('Authorization')!='Bearer TEST_ONLY_M55_PROTOCOL':self.send_error(403);return
  try:
   length=int(self.headers.get('Content-Length',0));assert 0<length<=65536
   request=json.loads(self.rfile.read(length));evidence=json.loads(request['messages'][1]['content'])['evidence']
   ids=[e['id'] for e in evidence[:12]]
   answer=json.dumps({'choices':[{'finish_reason':'stop','message':{'content':json.dumps({'evidence_ids':ids})}}]}).encode()
   self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(answer)));self.end_headers();self.wfile.write(answer)
  except Exception:self.send_error(400)
 def log_message(self,*args):pass
print('TEST_ONLY_M55 HTTP protocol fixture listening on loopback; no live vendor inference',flush=True)
ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
