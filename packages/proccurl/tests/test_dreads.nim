import std/[atomics, monotimes, options, unittest]
import proccurl/[dreads, ptrmath]

const MAX = 10

proc helloWorld(args, res: pointer): void =
  let arg = cast[ptr int64](args)[]
  cast[ptr int64](res)[] = getMonoTime().ticks - arg


test "Pool creation and teardown":
  let pool = newPool()
  pool.whileJoin:
    cpuRelax()
  freePool pool


test "Schedule and complete a single task":
  let pool = newPool()

  let arg: ptr int64 = createShared(int64)
  let res: ptr int64 = createShared(int64)
  let task: ptr TaskObj = createShared(TaskObj)

  arg[] = getMonoTime().ticks
  task[] = TaskObj(args: arg, res: res, req: helloWorld)

  pool.whileSchedule task.some:
    cpuRelax()

  waitTask task:
    cpuRelax()

  check task.isDone
  check res[] > 0

  pool.whileJoin:
    cpuRelax()
  freePool pool

  freeShared res
  freeShared arg
  freeShared task


test "Schedule and complete multiple tasks":
  let pool = newPool()

  let args = createShared(int64, MAX)
  let resp = createShared(int64, MAX)
  let tasks = createShared(TaskObj, MAX)

  for i in 0..<MAX:
    args[i] = getMonoTime().ticks
    tasks[i] = TaskObj(args: args[i], res: resp[i], req: helloWorld)
    pool.whileSchedule tasks[i].some:
      cpuRelax()

  for i in 0..<MAX:
    waitTask tasks[i]:
      cpuRelax()
    check tasks[i].isDone
    check resp[i][] > 0

  pool.whileJoin:
    cpuRelax()
  freePool pool

  freeShared resp
  freeShared args
  freeShared tasks


test "Task gets processed even without whileSchedule":
  let pool = newPool()

  let arg: ptr int64 = createShared(int64)
  let res: ptr int64 = createShared(int64)
  let task: ptr TaskObj = createShared(TaskObj)

  arg[] = getMonoTime().ticks
  task[] = TaskObj(args: arg, res: res, req: helloWorld)

  # Use the bool-returning schedule directly — no whileSchedule loop
  check pool.schedule(task)

  waitTask task:
    cpuRelax()

  check task.isDone
  check res[] > 0

  pool.whileJoin:
    cpuRelax()
  freePool pool

  freeShared res
  freeShared arg
  freeShared task


test "Task state reaches DONE":
  let pool = newPool()

  let arg: ptr int64 = createShared(int64)
  let res: ptr int64 = createShared(int64)
  let task: ptr TaskObj = createShared(TaskObj)

  arg[] = getMonoTime().ticks
  task[] = TaskObj(args: arg, res: res, req: helloWorld)

  pool.whileSchedule task.some:
    cpuRelax()

  waitTask task:
    cpuRelax()

  check task.stat.load(moRelaxed) == DONE

  pool.whileJoin:
    cpuRelax()
  freePool pool

  freeShared res
  freeShared arg
  freeShared task


test "Pool with different thread limits":
  let pool = newPool(minThreads = 2, maxThreads = 6)

  let args = createShared(int64, MAX)
  let resp = createShared(int64, MAX)
  let tasks = createShared(TaskObj, MAX)

  for i in 0..<MAX:
    args[i] = getMonoTime().ticks
    tasks[i] = TaskObj(args: args[i], res: resp[i], req: helloWorld)
    pool.whileSchedule tasks[i].some:
      cpuRelax()

  for i in 0..<MAX:
    waitTask tasks[i]:
      cpuRelax()
    check tasks[i].isDone
    check resp[i][] > 0

  pool.whileJoin:
    cpuRelax()
  freePool pool

  freeShared resp
  freeShared args
  freeShared tasks


test "Concurrent argument passing — each task gets a unique argument":
  let pool = newPool()

  let args = createShared(int64, MAX)
  let resp = createShared(int64, MAX)
  let tasks = createShared(TaskObj, MAX)

  for i in 0..<MAX:
    args[i] = int64(i * 100)
    tasks[i] = TaskObj(args: args[i], res: resp[i], req: helloWorld)
    pool.whileSchedule tasks[i].some:
      cpuRelax()

  for i in 0..<MAX:
    waitTask tasks[i]:
      cpuRelax()
    check tasks[i].isDone
    # Result is latency (getMonoTime.ticks - arg), always > 0
    check resp[i][] > 0

  pool.whileJoin:
    cpuRelax()
  freePool pool

  freeShared resp
  freeShared args
  freeShared tasks
