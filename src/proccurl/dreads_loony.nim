import std/[atomics, monotimes, options, typedthreads]
import ./[sleez, ptrmath]
import pkg/loony

##
## This is a thread pool, managed by ThreadManager (a different thread).
##
## If pool has less threads than minThreads (default is 4), ThreadManager will 
## create new WorkerThread, unless there already maxThreads (default is 8) of 
## WorkerThreads.
##
## In most cases we dequeue a WorkerThread from pool and assign a task to it.
##
## If the pool is empty or busy, we add it to a task queue. The task will be later
## dequeued by the ThreadManager and assigned to a thread.
##
## If task queue is empty, and there are more threads in the pool than minThreads,
## ThreadManager will scale down to minThreads.
##
## The main objective of this scruture is reduce the amount of lock in shared
## objects per tasks, but it uses spin locks, spin locks are faster 
##
## See the [diagram](https://coggle.it/diagram/ZtfGyMrvLIwlVhbU/t/main/2c837d2373a0dba51611b9ca5e2d1d687705477db3c60848b6519fe4dd430dae)
##
## See bench/dreads.nim for example.
##

runnableExamples:
  import proccurl/[ptrmath]
  import std/[monotimes, options]

  const MAX_ITEMS = 10
 
  # function to run in the thread
  proc helloWorld(args, res: pointer): void =
    # Read argument
    #              -- arg --        #
    let arg = cast[ptr int64](args)[]
    # Write to response
    #    -- res --                                   #
    cast[ptr int64](res)[] = getMonoTime().ticks - arg

  # Example with single schedule
  proc singleExample(pool: ptr Pool): void =
    # make room for shared data
    let arg:  ptr int64   = createShared(int64)
    let res:  ptr int64   = createShared(int64)
    let task: ptr TaskObj = createShared(TaskObj)

    # init argument 
    arg[] = getMonoTime().ticks

    # create a taskObj
    task[] = TaskObj(
      args: arg,
      res:  res,
      req:  helloWorld,
    )
  
    # schedule this task
    pool.whileSchedule task.some:
      # do something else if task isn't scheduled
      cpuRelax()

    # wait until the task complete
    waitTask task:
      # do something else if task isn't done
      cpuRelax()

    # do something with result
    assert task.isDone, "Task not DONE but " & $task.stat

    # free resources before we left the function
    defer:
      freeShared res
      freeShared arg
      freeShared task
  
  # example with array 
  proc arrayExample(pool: ptr Pool): void =
    # make room for shared data
    let args = createShared(int64,   MAX_ITEMS)
    let resp = createShared(int64,   MAX_ITEMS)
    let tasks = createShared(TaskObj, MAX_ITEMS)

    # schedule the tasks
    for i in 0..<MAX_ITEMS:
      args[i] = getMonoTime().ticks

      tasks[i] = TaskObj(
        args: args[i],
        res:  resp[i],
        req:  helloWorld,
      )
  
      pool.whileSchedule tasks[i].some:
        cpuRelax()

    # wait all tasks to complete
    for i in 0..<MAX_ITEMS:
      waitTask tasks[i]:
        cpuRelax()
  
    # do something with result
    for i in 0..<MAX_ITEMS:
      assert tasks[i].isDone, "Task " & $i & " not DONE but " & $tasks[i].stat
      debugEcho i, ": ", resp[0][]

    # free resources before we left the function
    defer:
      freeShared resp
      freeShared args
      freeShared tasks

  # async example
  import std/[asyncfutures, asyncdispatch]

  proc asyncExample(pool: ptr Pool): Future[int64] {.async.} =
    # make room for shared data
    let arg:  ptr int64   = createShared(int64)
    let res:  ptr int64   = createShared(int64)
    let task: ptr TaskObj = createShared(TaskObj)

    # free resources before we left the function
    defer:
      freeShared res
      freeShared arg
      freeShared task

    # init argument 
    arg[] = getMonoTime().ticks

    # create a taskObj
    task[] = TaskObj(
      args: arg,
      res:  res,
      req:  helloWorld,
    )
  
    # schedule this task
    pool.whileSchedule task.some:
      # return control to asyncdispatch
      await sleepAsync(0)

    # wait until the task complete
    waitTask task:
      # return control to asyncdispatch
      debugEcho getMonoTime().ticks - arg[]
      await sleepAsync(0)
      debugEcho getMonoTime().ticks - arg[]

    # do something with result
    return res[]

 
  proc main(): void =
    # init the pool
    let pool: ptr Pool =  newPool()

    arrayExample pool
    singleExample pool
    debugEcho "Async: ", waitFor asyncExample(pool)

    # free resources before we left the function
    defer:
      # wait all threads to die
      pool.whileJoin:
        cpuRelax()
      freePool pool

  main()


type
  Stat* = enum
    ## STATE MACHINE: NEW -> ENQUEUED -> WIP -> DONE
    NEW,           ## Task is new
    ENQUEUED,      ## Task was sent to alt queue to be sent later
    WIP,           ## thread is working on Task
    DONE,          ## thread completed Task work
   
  PoolStat* = enum
    ## STATE MACHINE: NEW -> RUN -> JOIN -> DEAD
    PSNEW,         ## Pool is new
    PSRUN,         ## Pool was sent to alt queue to be sent later
    PSJOIN,        ## Pool was sent to thread to work
    PSDEAD,        ## Pool is dead

  TaskObj* = object
    idx*:  int64
    stat*: Atomic[Stat]
    args*: pointer
    res*:  pointer
    fn*:   proc (args, res: pointer) {.nimcall, gcsafe.}

  Task* = ptr TaskObj
 
  WorkerThread = object
    ## When we are unsure about the state of thread
    ## This object should be single thread
    ## but hold shared info like stat and task
    idx:  int64
    pool: Pool
    thr:  Thread[SharedWorker]

  SharedWorker = ptr WorkerThread

  TaskQueue    = LoonyQueue[Task]
  WorkersQueue = LoonyQueue[SharedWorker]

  PoolObject = object
    epoch:       int64
    workersLen:  Atomic[int]
    state:       Atomic[int]
    tasksLen:    Atomic[int]
    minThreads:  int
    maxThreads:  int
    thrMng:      Thread[Pool]
    tasks:       TaskQueue
    workers:     WorkersQueue
    thrWorkers:  ptr UncheckedArray[WorkerThread]

  Pool* = ptr PoolObject

using
  pool: Pool

proc `=copy`*(dest: var TaskObj; o: TaskObj) {.error.} = discard

template len*(pool): int =
  ## The number of tasks
  pool.tasksLen.load(moRelaxed)

template size*(pool): int =
  ## The number of workers
  pool.workersLen.load(moRelaxed)


proc `$`*(task: Task): string =
  $cast[int64](task) & ":" & $task.idx

proc `$`*(pool): string =
  "(" & $cast[int64](pool) &
  ", epoch: "      & $pool.epoch &
  ", workersLen: " & $pool.size &
  ", tasks: "      & $pool.len &
  ", minThreads: " & $pool.minThreads &
  ", maxThreads: " & $pool.maxThreads

proc `$`*(worker: WorkerThread): string =
  "("        & $cast[int64](worker.addr) &
  ", idx: "  & $worker.idx &
  ", pool: " & $worker.pool &
  ", thr: "  & $worker.thr & ")"

proc `$`*(worker: SharedWorker): string =
  $worker[]

template isDone*(task: Task): bool =
  task.stat.load(moRelaxed) == DONE


template waitTask*(task: Task; op: untyped): void =
  var stat {.inject.} = task.stat.load(moRelaxed)
  while stat != DONE:
    op
    stat = task.stat.load(moRelaxed)


template freePool*(pool): void =
  GC_unref pool.tasks
  GC_unref pool.workers
  freeShared pool


template whileJoin*(pool; op: untyped): void =
  pool.state.store(PSJOIN.int.static, moRelaxed)
  while pool.size > 0 or pool.len  > 0:
    assert pool != nil
    op
  pool.state.store(PSDEAD.int.static, moRelaxed)

using
  thr: SharedWorker


proc schedule(tq: TaskQueue; task: sink Option[Task]): Option[Task] =
  ## Because task cannot have copies
  ## Returns the task if task queue is unavailable
  ## Returns none(task) if operation succeed
  if task.isSome:
    task.get.stat.store ENQUEUED
    push(tq, task.get)
  return none[Task]()


proc schedule*(pool; task: sink Option[Task]): Option[Task] =
  result = pool.tasks.schedule task
  if result.isNone:
    pool.tasksLen.atomicInc


template whileSchedule*(pool; v: sink Option[Task]; op: untyped): void =
  var vv = v

  while vv.isSome and pool.state.load(moRelaxed) != PSDEAD.int.static:
    vv = pool.schedule vv
    if vv.isSome:
      op


proc invoke(pool): bool =
  ## Execute the task
  ## Return state if thread was available
  let task = pop[Task](pool.tasks)
  result = task != nil
  if result:
    var expected = ENQUEUED
    try:
      doAssert task.stat.compareExchange(expected, WIP,  moAcquire, moRelaxed), "expected SENT but it: " & $expected
      task.fn task.args, task.res
    finally:
      expected = WIP
      doAssert task.stat.compareExchange(expected, DONE, moRelease, moRelaxed), "expected wip but is: " & $expected
      pool.tasksLen.atomicDec


proc threadWorker(thr) {.thread.} =
  let w = pop[SharedWorker](thr.pool.workers)
  if w != nil and
     w.pool.size < w.pool.len:
    w.pool.workersLen.atomicInc
    createThread w.thr, threadWorker, w
  elif w != nil:
    push(thr.pool.workers, w)
  
  var spinner = progSpin
  while thr.pool.state.load(moRelaxed) == PSRUN.int.static or
        thr.pool.len > 0:
    if thr.pool.invoke:
      spinner = progSpin
    discard spinner()

  push(thr.pool.workers, thr)
  thr.pool.workersLen.atomicDec


proc threadCreator(pool) {.thread.} =
  var spinner = progSpin
  while pool.state.load(moRelaxed) == PSRUN.int.static or pool.len > 0:
    if pool.size < pool.minThreads or
      (pool.size < pool.maxThreads and
       pool.size < pool.len):
      # fewer threads, scalling up
      spinner = progSpin
      let w = pop[SharedWorker](pool.workers)
      if w != nil:
        pool.workersLen.atomicInc
        createThread w.thr, threadWorker, w
      spinner = progSpin
    elif pool.size == pool.maxThreads and
         pool.invoke():
      spinner = progSpin
    discard spinner()


proc initPool(
  pool: Pool;
  minThreads: int = 4;
  maxThreads: int = 8): void =
  ## Init a thread pool of minThreads up to maxThreads
  ##
  ## `minThreads` is the minimum free threads system starts to creating a more thread.
  ##
  ## `maxThreads` is the maximum free threads system starts to finishing threads.
  ##
  ## Must be +2 greater than `minThreads`. 
  ##
  ## Usually it keeps `minThreads` running.
  assert minThreads + 2 < maxThreads, "maxThreads must be greater than minThreads + 2"
  pool.epoch = getMonoTime().ticks
  pool.minThreads = minThreads
  pool.maxThreads = maxThreads
  pool.state.store(PSRUN.int.static)
  pool.workersLen.store(0, moRelaxed)
  pool.thrWorkers = cast[ptr UncheckedArray[WorkerThread]](pool + 1)
  pool.workers = newLoonyQueue[SharedWorker]()
  pool.tasks = newLoonyQueue[Task]()
  GC_ref pool.workers
  GC_ref pool.tasks
  createThread(
    pool.thrMng,
    threadCreator,
    pool
  )
  for i in 0..<pool.maxThreads:
    pool.thrWorkers[i].pool = pool
    pool.thrWorkers[i].idx  = i
    push(pool.workers, pool.thrWorkers[i].addr)


proc newPool*(minThreads: int = 4; maxThreads: int = 8): Pool {.discardable.} =
  ## Create a thread pool of minThreads up to maxThreads
  ##
  ## `minThreads` is the minimum free threads system starts to creating a more thread.
  ##
  ## `maxThreads` is the maximum free threads system starts to finishing threads.
  ##
  ## Must be +2 greater than `minThreads`. 
  ##
  ## Usually it keeps `minThreads` running.

  let memory  = createShared(byte,
    sizeof(PoolObject) +
    (sizeOf(WorkerThread) * maxThreads)
  )
  result = cast[Pool](memory)
  initPool(
    result,
    minThreads,
    maxThreads
  )
