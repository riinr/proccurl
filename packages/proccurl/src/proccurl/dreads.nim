import std/[atomics, monotimes, options, times, typedthreads]
import ./boring
import ./sleez

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


const WORKER_SLOTS* {.intdefine: "dreads.workerslots".} = 1024
const TASK_SLOTS*   {.intdefine: "dreads.taskslots".}   = 1024

type
  WorkerStat = enum
    ## STATE MACHINE: DONE -> TAKEN -> TO DO -> RUNNING -> DONE
    WSDEAD,  ## thread isn't running
    WSDONE,  ## thread is free to work
    WSTAKEN, ## thread was taken by someone
    WSTODO,  ## thread has task to run
    WSWIP,   ## thread is running the task
    WSDIE,   ## thread must be finished
   
  Stat* = enum
    ## STATE MACHINE: NEW -> ENQUEUED -> SENT -> WIP -> DONE
    NEW,           ## Task is new
    ENQUEUED,      ## Task was sent to alt queue to be sent later
    SENT,          ## Task was sent to thread to work
    WIP,           ## thread is working on Task
    DONE,          ## thread completed Task work
   
  PoolStat* = enum
    ## STATE MACHINE: DEAD -> RUN -> JOIN -> DEAD
    PSDEAD,        ## Task is new
    PSRUN,         ## Task was sent to alt queue to be sent later
    PSJOIN,        ## Task was sent to thread to work

  TaskObj* = object
    idx*:  int64
    stat*: Atomic[Stat]
    args*: pointer
    res*:  pointer
    req*:  proc (args, res: pointer) {.nimcall, gcsafe.}

  Task* = ptr TaskObj
 
  WorkerThread = object
    ## When we are unsure about the state of thread
    ## This object should be single thread
    ## but hold shared info like stat and task
    stat: Atomic[int]   ## thread status
    task: Option[Task]  ## thread task/response
    pool: Pool
    thr:  Thread[SharedWorker]

  SharedWorker = ptr WorkerThread

  WorkerQueue = Queue[WORKER_SLOTS, MP[WORKER_SLOTS], MC[WORKER_SLOTS], SharedWorker]
  TaskQueue   = Queue[TASK_SLOTS,   MP[TASK_SLOTS],   MC[TASK_SLOTS],   Task]

  PoolObject* = object
    epoch*:      int64
    numThreads:  Atomic[int]
    state:       Atomic[int]
    minThreads:  int
    maxThreads:  int
    thrMng:      Thread[Pool]
    workerQueue: WorkerQueue
    taskQueue:   TaskQueue
    workers:     UncheckedArray[WorkerThread]

  Pool = ptr PoolObject


proc `=copy`*(dest: var TaskObj; o: TaskObj) {.error.} = discard


proc `$`*(task: Task): string =
  $cast[int64](task) & ":" & $task.idx

proc `$`*(worker: SharedWorker): string =
  $cast[int64](worker)

proc isDone*(task: Task): bool =
  task.stat.load(moRelaxed) == DONE


template waitTask*(task: Task; op: untyped): void =
  var stat {.inject.} = task.stat.load(moRelaxed)
  while stat != DONE:
    op
    stat = task.stat.load(moRelaxed)


using
  pool: Pool


template len(q: ptr WorkerQueue): int =
  let p = cast[uint32](q.producer)
  let c = cast[uint32](q.consumer)
  cast[int]((p - c + WORKER_SLOTS) mod WORKER_SLOTS)


template len(q: ptr TaskQueue): int =
  let p = cast[uint32](q.producer)
  let c = cast[uint32](q.consumer)
  cast[int]((p - c + TASK_SLOTS) mod TASK_SLOTS)


template freePool*(pool): void =
  freeShared pool


template whileJoin*(pool; op: untyped): void =
  pool.state.store(PSJOIN.int.static, moRelaxed)
  while pool.numThreads.load > 0:
    op


using
  thr: SharedWorker


proc schedule(thr; task: sink Option[Task]): Option[Task] =
  var expected = WSDONE.int.static
  if task.isNone or not thr.stat.compareExchange(expected, WSTAKEN.int.static, moAcquire, moRelaxed):
    return task

  result = none[Task]()
  try:
    task.get.stat.store SENT
    thr.task = task
  finally:
    expected = WSTAKEN.int.static
    const desired = WSTODO.int.static
    doAssert thr.stat.compareExchange(expected, desired, moRelease, moRelaxed)


proc scheduleDie(thr): bool =
  var  expected = WSDONE.int.static
  const desired = WSTAKEN.int.static
  result = thr.stat.compareExchange(expected, desired, moAcquire, moRelaxed) or
    expected == WSDEAD.int.static or
    expected == WSDIE.int.static
  if result:
    thr.stat.store WSDIE.int.static


proc schedule(wq: ptr WorkerQueue; task: sink Option[Task]): Option[Task] =
  ## Because task cannot have copies
  ## Returns the task if no thread is available
  ## Returns none(task) if operation succeed
  result = task
  if result.isSome:
    let optThr = wq.dequeue(SharedWorker)
    if optThr.isSome:
      var spinner = progSpin
      while result.isSome and
          optThr.get.stat.load(moRelaxed) != WSDIE.int.static and
          optThr.get.stat.load(moRelaxed) != WSDEAD.int.static:
        result = optThr.get.schedule result
        if result.isSome:
          discard spinner()


proc schedule(tq: ptr TaskQueue; task: sink Option[Task]): Option[Task] =
  ## Because task cannot have copies
  ## Returns the task if task queue is unavailable
  ## Returns none(task) if operation succeed
  if task.isSome:
    task.get.stat.store ENQUEUED
    if not tq.enqueue(task.get):
      task.get.stat.store NEW
      return task

  return none[Task]()


proc schedule*(pool; task: sink Option[Task]): Option[Task] =
  result = pool.workerQueue.addr.schedule task
  if result.isSome:
    result = pool.taskQueue.addr.schedule result


proc schedule*(pool; task: Task): bool =
  pool.schedule(task.some).isNone


template whileSchedule*(pool; v: sink Option[Task]; op: untyped): void =
  var vv = v

  while vv.isSome and pool.state.load(moRelaxed) != PSDEAD.int.static:
    vv = pool.schedule vv
    if vv.isSome:
      op


proc scheduleDie*(wq: ptr WorkerQueue): bool =
  let optT = wq.dequeue(SharedWorker)
  result = optT.isSome
  if result:
    let thr = optT.get
    var spinner = progSpin
    while not thr.scheduleDie:
      discard spinner()


proc enqueue(thr): void =
  var spinner = progSpin
  var t = thr
  while thr.pool.workerQueue.addr.enqueue t:
    discard spinner()


proc invoke(thr): int =
  ## Execute the task
  ## Return state if thread was available
  result = WSTODO.int.static
  if thr.stat.compareExchange(result, WSWIP.int.static, moAcquireRelease, moRelaxed):
    if thr.task.isSome:
      try:
        var expcted = SENT
        doAssert thr.task.get.stat.compareExchange(expcted, WIP, moAcquire, moRelaxed)
        thr.task.get.req thr.task.get.args, thr.task.get.res
      finally:
        var expcted = WIP
        doAssert thr.task.get.stat.compareExchange(expcted, DONE, moRelease, moRelaxed)
    var expected = WSWIP.int.static
    doAssert thr.stat.compareExchange(expected, WSDONE.int.static, moAcquireRelease, moRelaxed)


proc threadWorker(thr) {.thread.} =
  for i in 0..<thr.pool.maxThreads:
    if thr.pool.numThreads.load(moRelaxed) < thr.pool.maxThreads and
       thr.pool.numThreads.load(moRelaxed) < thr.pool.taskQueue.addr.len:
      var expected = WSDEAD.int.static
      if thr.pool.workers[i].stat.compareExchange(expected, WSDONE.int.static, moAcquireRelease, moRelaxed):
        thr.pool.numThreads.atomicInc
        thr.pool.workers[i].pool = thr.pool
        createThread thr.pool.workers[i].thr, threadWorker, thr.pool.workers[i].addr
        break
    else:
      break
  
  # var task: Option[Task]
  # while true:
  #   task = thr.pool.taskQueue.addr.dequeue(Task)
  #   if task.isSome:
  #     task = thr.schedule(task)
  #     assert task.isNone
  #     discard thr.invoke
  #   else:
  #     break

  var spinner = progSpin

  # Enqueue this thread as resource
  thr.enqueue()

  var oldStat = -1
  while true:
    oldStat = thr.invoke

    if oldStat == WSDIE.int.static or thr.pool.state.load(moRelaxed) == PSDEAD.int.static:
      break

    # Enequeue this thread back
    if oldStat == WSTODO.int.static:
      thr.enqueue()
      spinner = progSpin
      continue

    # reset spinner because someone is almost scheduling a task
    if oldStat == WSTAKEN.int.static:
      spinner = progSpin

    discard spinner()

  defer:
    thr.stat.store(WSDEAD.int.static, moAcquireRelease)
    thr.pool.numThreads.atomicDec


proc threadManager(pool) {.thread.} =
  pool.state.store(PSRUN.int.static, moRelaxed)
  var spinner = progSpin
  var task = none[Task]()
  while true:
    if pool.state.load(moRelaxed) == PSJOIN.int.static and pool.taskQueue.addr.len == 1:
      break
    elif pool.numThreads.load(moRelaxed) < pool.minThreads or
          (pool.numThreads.load(moRelaxed) < pool.maxThreads and
           pool.taskQueue.addr.len > pool.numThreads.load(moRelaxed)):
      # fewer threads, scalling up
      for i in 0..<pool.maxThreads:
        var expected = WSDEAD.int.static
        if pool.workers[i].stat.compareExchange(expected, WSDONE.int.static, moAcquireRelease, moRelaxed):
          pool.numThreads.atomicInc
          pool.workers[i].pool = pool
          createThread pool.workers[i].thr, threadWorker, pool.workers[i].addr
          break
    elif pool.taskQueue.addr.len == 0 and pool.workerQueue.addr.len > pool.minThreads:
      discard pool.workerQueue.addr.scheduleDie

    if task.isNone:
      task = pool.taskqueue.addr.dequeue(Task)

    if task.isSome:
      spinner = progspin
      task = pool.workerqueue.addr.schedule task
      continue

    discard spinner()

  spinner = progSpin
  while pool.taskQueue.addr.len > 0:
    if task.isNone:
      task = pool.taskQueue.addr.dequeue(Task)
  
    if task.isSome:
      task = pool.workerQueue.addr.schedule task
    discard spinner()

  spinner = progSpin
  while pool.numThreads.load(moRelaxed) > 1:
    pool.state.store(PSDEAD.int.static, moRelaxed)
    discard pool.workerQueue.addr.scheduleDie
    discard spinner()

  defer:
    pool.numThreads.atomicDec


proc initPool*(
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
  assert maxThreads <= WORKER_SLOTS,  "maxThreads exceeds WORKER_SLOTS"
  pool.epoch = getMonoTime().ticks
  pool.minThreads = minThreads
  pool.maxThreads = maxThreads
  pool.state.store(PSRUN.int.static)
  pool.numThreads.store(0, moRelaxed)

  createThread(
    pool.thrMng,
    threadManager,
    pool
  )


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
    sizeof(PoolObject) + (sizeOf(WorkerThread) * maxThreads)
  )
  result = cast[Pool](memory)
  #result.workers = cast[UncheckedArray[WorkerThread]](cast[int64]())
  initPool(
    result,
    minThreads,
    maxThreads
  )
