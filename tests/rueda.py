import json, socket, sys, time
SOCK="/tmp/mikeos-qmp.sock"; ANCHO,ALTO=1920,1080
def q(s,c):
    s.sendall((json.dumps(c)+"\n").encode()); time.sleep(0.2)
    try: return s.recv(65536).decode()
    except Exception: return ""
x,y,direccion,veces = int(sys.argv[1]),int(sys.argv[2]),sys.argv[3],int(sys.argv[4])
s=socket.socket(socket.AF_UNIX); s.connect(SOCK); s.settimeout(2); s.recv(65536)
q(s,{"execute":"qmp_capabilities"})
q(s,{"execute":"input-send-event","arguments":{"events":[
    {"type":"abs","data":{"axis":"x","value":int(x*32767/ANCHO)}},
    {"type":"abs","data":{"axis":"y","value":int(y*32767/ALTO)}}]}})
time.sleep(0.4)
for _ in range(veces):
    q(s,{"execute":"input-send-event","arguments":{"events":[
        {"type":"btn","data":{"button":direccion,"down":True}}]}})
    q(s,{"execute":"input-send-event","arguments":{"events":[
        {"type":"btn","data":{"button":direccion,"down":False}}]}})
    time.sleep(0.5)
print(f"rueda {direccion} x{veces} sobre ({x},{y})")
