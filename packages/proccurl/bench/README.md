# Benchmarks

- **Disclaimer**: [Benchmarking Is Hard](https://jvns.ca/blog/2016/07/23/rigorous-benchmarking-in-reasonable-time/)
- **Disclaimer**: [Operation Costs in CPU Clock Cycles](http://ithare.com/infographics-operation-costs-in-cpu-clock-cycles/)

The main objective is meausre noise of this library. But we also measure other
libraries for reference.

We do that taking the time before the function call, inside the function, and
after the function.

```nim
proc fn(t1: var MonoTime): void =
  t1 = getMonoTime()


let t0 = getMonoTime()
var t1: MonoTime
schedule fn(t1)         # await/send/schedule if is the case
let t2 = getMonoTime()

let send   = t2 - t0    # How much time it takes to schedule the task,
                        # makes more sense in threads where is may spend
                        # time waiting for locks

let latency = t1 - t0   # How much time it takes to other thread run
                        # this task. again makes more sense in threads
```


We run that 1000 times, get the 5 most commons results.

## Results:


### reference
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 151ns |  | Initializing |
| Send 100% |  | 117us132ns | 117ns/task | To schedule tasks |
| Send | 68% | 086ns~088ns |  | 684 tasks |
| Send | 14% | 088ns~090ns |  | 142 tasks |
| Send | 10% | 090ns~092ns |  | 106 tasks |
| Send | 04% | 084ns~086ns |  | 044 tasks |
| Send | 02% | 092ns~094ns |  | 020 tasks |
| Latency | 78% | 028ns~026ns |  | 785 tasks |
| Latency | 12% | 026ns~024ns |  | 127 tasks |
| Latency | 08% | 030ns~028ns |  | 086 tasks |
| Latency | 00% | 032ns~030ns |  | 001 tasks |
| Join |  | 038ns |  | Waiting all tasks to complete |
| Snd+Join |  | 117us170ns | 117ns/task | Send + Join |
| Total |  | 117us386ns |  |  |

   This version, doesn't use any asynch/thread feature, just function call

   We are years away from this.


### async
   
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 331ns |  | Initializing |
| Send 100% |  | 284us002ns | 284ns/task | To schedule tasks |
| Send | 51% | 225ns~250ns |  | 513 tasks |
| Send | 48% | 250ns~275ns |  | 483 tasks |
| Send | 00% | 350ns~375ns |  | 001 tasks |
| Send | 00% | 525ns~550ns |  | 001 tasks |
| Send | 00% | 300ns~325ns |  | 001 tasks |
| Latency | 33% | 096ns~094ns |  | 337 tasks |
| Latency | 18% | 100ns~098ns |  | 187 tasks |
| Latency | 14% | 094ns~092ns |  | 142 tasks |
| Latency | 13% | 104ns~102ns |  | 131 tasks |
| Latency | 11% | 098ns~096ns |  | 111 tasks |
| Join |  | 046ns |  | Waiting all tasks to complete |
| Snd+Join |  | 284us048ns | 284ns/task | Send + Join |
| Total |  | 284us443ns |  |  |

    Nim std lib async/dispatch
 

### asyncchronos
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 300ns |  | Initializing |
| Send 100% |  | 427us110ns | 427ns/task | To schedule tasks |
| Send | 46% | 350ns~375ns |  | 462 tasks |
| Send | 38% | 375ns~400ns |  | 383 tasks |
| Send | 14% | 325ns~350ns |  | 145 tasks |
| Send | 00% | 400ns~425ns |  | 003 tasks |
| Send | 00% | 525ns~550ns |  | 002 tasks |
| Latency | 14% | 154ns~152ns |  | 140 tasks |
| Latency | 11% | 146ns~144ns |  | 119 tasks |
| Latency | 10% | 152ns~150ns |  | 109 tasks |
| Latency | 09% | 148ns~146ns |  | 093 tasks |
| Latency | 08% | 142ns~140ns |  | 087 tasks |
| Join |  | 038ns |  | Waiting all tasks to complete |
| Snd+Join |  | 427us148ns | 427ns/task | Send + Join |
| Total |  | 427us496ns |  |  |


Same benchmark using Async/Await with [Chronos](https://github.com/status-im/nim-chronos)


### dreads
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 112us476ns |  |  |
| Send¹ | 98% | 000ns~200ns |  | 988 tasks |
| Send¹ | 01% | 200ns~400ns |  | 010 tasks |
| Send¹ | 00% | 600ns~800ns |  | 001 tasks |
| Total sending |  | 207us977ns | 207ns/task | To schedule tasks |
| Latency² | 00% | 005ms892us000ns~005ms893us000ns |  | 003 tasks |
| Latency² | 00% | 041ms713us000ns~041ms714us000ns |  | 003 tasks |
| Latency² | 00% | 004ms891us000ns~004ms892us000ns |  | 003 tasks |
| Latency² | 00% | 017ms962us000ns~017ms963us000ns |  | 003 tasks |
| Latency² | 00% | 022ms945us000ns~022ms946us000ns |  | 003 tasks |
| Join |  | 043ms717us875ns |  | Waiting all tasks to complete |
| Snd+Join |  | 043ms925us852ns | 043us925ns/task | Send + Join |
| Total |  | 044ms038us532ns |  |  |

    Dreads principle:

    Instead of a queue of tasks, have a queue of workers.

    Who ever needs a task done, pop a worker from queue and set a task.

    With a fallback to queue of tasks, managed by ThreadManager, that creates and kill threads.

    The idea was reduce contention.

    STILL in progress
    


### dreads_loony
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 093us832ns |  |  |
| Send¹ | 98% | 050ns~100ns |  | 984 tasks |
| Send¹ | 01% | 100ns~150ns |  | 010 tasks |
| Send¹ | 00% | 150ns~200ns |  | 004 tasks |
| Send¹ | 00% | 001us100ns~001us150ns |  | 001 tasks |
| Total sending |  | 129us641ns | 129ns/task | To schedule tasks |
| Latency² | 79% | 400us000ns~450us000ns |  | 791 tasks |
| Latency² | 20% | 350us000ns~400us000ns |  | 208 tasks |
| Join |  | 441us185ns |  | Waiting all tasks to complete |
| Snd+Join |  | 570us826ns | 570ns/task | Send + Join |
| Total |  | 664us841ns |  |  |
    
    Is dreads, but using [loony](https://github.com/nim-works/loony) instead of my own implementation of RingBuffer.

    Since Loony is super fast, keep it simple and use only the task queue for scheduling tasks.

    Idea behind dreads was reduce contention, but loony has other ways to make things fast:.
    


### dreads_loony_workers
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 087us010ns |  |  |
| Send¹ | 50% | 400ns~600ns |  | 506 tasks |
| Send¹ | 38% | 200ns~400ns |  | 387 tasks |
| Send¹ | 08% | 600ns~800ns |  | 085 tasks |
| Send¹ | 01% | 800ns~001us000ns |  | 014 tasks |
| Send¹ | 00% | 001us000ns~001us200ns |  | 003 tasks |
| Total sending |  | 552us870ns | 552ns/task | To schedule tasks |
| Latency² | 52% | 600ns~800ns |  | 527 tasks |
| Latency² | 23% | 400ns~600ns |  | 237 tasks |
| Latency² | 19% | 800ns~001us000ns |  | 194 tasks |
| Latency² | 02% | 001us000ns~001us200ns |  | 028 tasks |
| Latency² | 00% | 001us200ns~001us400ns |  | 004 tasks |
| Join |  | 056us008ns |  | Waiting all tasks to complete |
| Snd+Join |  | 608us878ns | 608ns/task | Send + Join |
| Total |  | 001ms064us827ns |  |  |

    Same idea of dreads_loony, but instead of removing Workers queue from Dreads, it removes TaskQueue from Dreads.

    Means no fallback to taskqueue, only direct assign to workers in queue.
    


### malebolgiabench
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 476ns |  | Malebolgia setup wasn't properly measured |
| Send¹ | 23% | 800ns~001us600ns |  | 238 tasks |
| Send¹ | 21% | 002us400ns~003us200ns |  | 211 tasks |
| Send¹ | 12% | 003us200ns~004us000ns |  | 128 tasks |
| Send¹ | 12% | 001us600ns~002us400ns |  | 120 tasks |
| Send¹ | 08% | 000ns~800ns |  | 085 tasks |
| Total sending |  | 003ms110us970ns | 003us110ns/task | To schedule tasks |
| Latency² | 15% | 004us000ns~005us000ns |  | 156 tasks |
| Latency² | 14% | 005us000ns~006us000ns |  | 144 tasks |
| Latency² | 12% | 003us000ns~004us000ns |  | 124 tasks |
| Latency² | 11% | 006us000ns~007us000ns |  | 113 tasks |
| Latency² | 09% | 007us000ns~008us000ns |  | 097 tasks |
| Join |  | 008us716ns |  | Waiting all tasks to complete |
| Snd+Join |  | 003ms119us686ns | 003us119ns/task | Send + Join |
| Total |  | 003ms120us199ns |  |  |

    Same benchmark, using [Malebolgia](https://github.com/Araq/malebolgia)
    

    


### threads
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 017us553ns |  |  |
| Send¹ | 72% | 020us000ns~030us000ns |  | 721 tasks |
| Send¹ | 23% | 030us000ns~040us000ns |  | 233 tasks |
| Send¹ | 03% | 040us000ns~050us000ns |  | 031 tasks |
| Send¹ | 00% | 060us000ns~070us000ns |  | 003 tasks |
| Send¹ | 00% | 050us000ns~060us000ns |  | 002 tasks |
| Total sending |  | 029ms869us728ns | 029us869ns/task | To schedule tasks |
| Latency² | 77% | 030us000ns~040us000ns |  | 777 tasks |
| Latency² | 13% | 040us000ns~050us000ns |  | 134 tasks |
| Latency² | 03% | 020us000ns~030us000ns |  | 037 tasks |
| Latency² | 02% | 050us000ns~060us000ns |  | 022 tasks |
| Latency² | 00% | 110us000ns~120us000ns |  | 005 tasks |
| Join |  | 007ms352us369ns |  | Waiting all tasks to complete |
| Snd+Join |  | 037ms222us097ns | 037us222ns/task | Send + Join |
| Total |  | 037ms239us747ns |  |  |

    Naive thread implementation, no pool, just thread creation for each task

    The main issue with this version, is that createThread, blocks the mainThread.
    


### weavebench
| Section | % | Time | Avg | Description |
|---|---:|---:|---:|---|
| Tasks |  |  |  | 1000 tasks |
| Setup |  | 001ms003us355ns |  |  |
| Send¹ | 95% | 000ns~200ns |  | 958 tasks |
| Send¹ | 00% | 012us200ns~012us400ns |  | 009 tasks |
| Send¹ | 00% | 200ns~400ns |  | 005 tasks |
| Send¹ | 00% | 012us000ns~012us200ns |  | 004 tasks |
| Send¹ | 00% | 015us800ns~016us000ns |  | 003 tasks |
| Total sending |  | 580us019ns | 580ns/task | To schedule tasks |
| Latency² | 17% | 000ns~100us000ns |  | 174 tasks |
| Latency² | 15% | 100us000ns~200us000ns |  | 156 tasks |
| Latency² | 15% | 500us000ns~600us000ns |  | 155 tasks |
| Latency² | 15% | 300us000ns~400us000ns |  | 155 tasks |
| Latency² | 15% | 400us000ns~500us000ns |  | 155 tasks |
| Join |  | 072us567ns |  | Waiting all tasks to complete |
| Snd+Join |  | 652us586ns | 652ns/task | Send + Join |
| Total |  | 001ms660us621ns |  |  |

    Same benchmark using [weave](https://github.com/mratsim/weave) lib
   
