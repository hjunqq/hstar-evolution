import json,collections,bisect,sys,importlib.util
S=sys.argv[1]
spec=importlib.util.spec_from_file_location("inv","tools/yl_io_inventory.py"); inv=importlib.util.module_from_spec(spec); spec.loader.exec_module(inv)
rows=collections.defaultdict(list); cur=None
for ln in open(S+"/lt-final.txt",errors='replace'):
    m=inv.LINE_TABLE_SYMTAB.match(ln)
    if m: cur=m.group(1).rsplit('/',1)[-1]; continue
    if cur is None: continue
    m=inv.LINE_TABLE_ROW.match(ln)
    if m: rows[cur].append((int(m.group(1)), None if m.group(2)=='END' else int(m.group(2)), int(m.group(3),16)))
iv=collections.defaultdict(lambda: collections.defaultdict(list))
for f,rs in rows.items():
    rs.sort(key=lambda r:r[0])
    for i,(idx,line,addr) in enumerate(rs):
        if line is None: continue
        iv[f][line].append((addr, rs[i+1][2] if i+1<len(rs) else addr))
ins=sorted(int(x,16) for x in open(S+"/insns.txt"))
hits=set(json.load(open("docs/m1/evidence/cooks_membrane/hits.json"))["hits"])|set(json.load(open("docs/m1/evidence/lame_cylinder/hits.json"))["hits"])
sites=[s for s in json.load(open('docs/m1/io-sites.json'))['sites'] if s['site'] not in hits]
out=["set pagination off","set confirm off","set breakpoint pending on","set print thread-events off",
     "set logging file "+S+"/insn-hits.log","set logging overwrite on","set logging redirect on","set logging enabled on"]
n=0
for s in sites:
    addrs=set()
    for a,b in iv.get(s['file'],{}).get(s['line'],[]):
        addrs.update(ins[bisect.bisect_left(ins,a):bisect.bisect_left(ins,b)])
    for a in sorted(addrs):
        out += ["break *%#x" % a,"commands","silent",'printf "HIT %s %#x\\n"' % (s["site"],a),"continue","end"]; n+=1
out += ['printf "LOCATIONS %%d %d\\n", $bpnum' % n,"run < /dev/null > gdb-stdout.txt 2> gdb-stderr.txt",'printf "EXIT %d\\n", $_exitcode',"quit"]
open(S+"/insn.gdb","w").write("\n".join(out)+"\n")
print("locations",n,"sites",len(sites))
