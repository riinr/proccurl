import std/tables
import proccurl/sleez

type
  Perc* = object
    tot*: int
    part*: int

  Pos* = object
    time*: int64
    count*: int
    perc*: Perc

  Top* = tuple
    st1: Pos
    nd2: Pos
    rd3: Pos
    th4: Pos
    th5: Pos


proc `$`*(p: Perc): string =
  let i = (100 * p.part) div p.tot
  if i < 10:
     "0" & $i & "%"
  else:
    $i & "%"


proc cluster(i: int64; d: int): int64 =
  i div d * d


proc top_items*(a, b: ptr UncheckedArray[int64]; clstr, I: int): Top =
  var h = initTable[int64, int]()

  for i in 1..<I:
    let k = cluster(b[i] - a[i], clstr)
    discard h.hasKeyOrPut(k, 0)
    h[k].inc

  var st1: Pos
  var nd2: Pos
  var rd3: Pos
  var th4: Pos
  var th5: Pos

  for k, v in h.pairs():
    if   v > st1.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = st1.time
      nd2.count = st1.count
      st1.time  = k + clstr
      st1.count = v
    elif v > nd2.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = k + clstr
      nd2.count = v
    elif v > rd3.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = k + clstr
      rd3.count = v
    elif v > th4.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = k + clstr
      th4.count = v
    elif v > th5.count:
      th5.time  = k + clstr
      th5.count = v
  st1.perc = Perc(tot: I, part: st1.count)
  nd2.perc = Perc(tot: I, part: nd2.count)
  rd3.perc = Perc(tot: I, part: rd3.count)
  th4.perc = Perc(tot: I, part: th4.count)
  th5.perc = Perc(tot: I, part: th5.count)
  (st1, nd2, rd3, th4, th5)


template zeroFill*(t: int64): string =
  if   t < 010: "00" & $t
  elif t < 100:  "0" & $t
  else:                $t


proc printCluster*(st, nd, rd, th, fth: Pos; rng: int; label: string) =
  if st.count > 0: echo label, st.perc, ":\t", (st.time - rng).ns, "~", st.time.ns, "\t", st.count.zeroFill, " tasks"
  if nd.count > 0: echo label, nd.perc, ":\t", (nd.time - rng).ns, "~", nd.time.ns, "\t", nd.count.zeroFill, " tasks"
  if rd.count > 0: echo label, rd.perc, ":\t", (rd.time - rng).ns, "~", rd.time.ns, "\t", rd.count.zeroFill, " tasks"
  if th.count > 0: echo label, th.perc, ":\t", (th.time - rng).ns, "~", th.time.ns, "\t", th.count.zeroFill, " tasks"
  if fth.count > 0: echo label, fth.perc, ":\t", (fth.time - rng).ns, "~", fth.time.ns, "\t", fth.count.zeroFill, " tasks"


proc printTotalSending*(total, perTask: int64) =
  echo "Total sending:\t", total.ns, perTask.ns, "/task\t", "To schedule tasks"


proc printJoinSummary*(join, sndJoin, total: int64; n: int) =
  echo "Join:     \t", join.ns, "\t", "         \t", "Waiting all tasks to complete"
  echo "Snd+Join: \t", sndJoin.ns, (sndJoin div n).ns, "/task\t", "Send + Join"
  echo "Total:    \t", total.ns
